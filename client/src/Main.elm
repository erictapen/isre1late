-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (main)

import Browser exposing (UrlRequest(..))
import Browser.Events exposing (onAnimationFrameDelta)
import Browser.Navigation
import Dict exposing (Dict)
import Html as H exposing (Html, button, div, h1, text)
import Html.Attributes as HA exposing (class, id, style)
import Html.Events exposing (onClick)
import Html.Events.Extra.Touch as Touch
import Json.Decode as JD exposing (decodeString)
import List exposing (filterMap, head, indexedMap, map)
import Model
    exposing
        ( Direction(..)
        , DistanceMatrix
        , Mode(..)
        , ModeTransition
        , Model
        , buildUrl
        , initDistanceMatrix
        , stationNames
        , stations
        , urlParser
        )
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg)
import Svg.Attributes as SA
    exposing
        ( d
        , fill
        , fontSize
        , height
        , preserveAspectRatio
        , stroke
        , strokeWidth
        , viewBox
        , width
        , x
        , x1
        , x2
        , y
        , y1
        , y2
        )
import Svg.Loaders
import Task
import Time exposing (Posix, posixToMillis)
import Types exposing (DelayRecord, StationId, TripId, decodeClientMsg)
import Url
import Url.Builder
import Url.Parser as UP
import Utils exposing (touchCoordinates)


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port rebuildSocket : String -> Cmd msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ messageReceiver RecvWebsocket

        -- TODO synchronise this with RecvWebsocket after the loading state is implemented
        , Time.every 1000 CurrentTime
        , case ( model.modeTransition.progress /= 0, model.modeTransition.touchState ) of
            ( True, Nothing ) ->
                onAnimationFrameDelta AnimationFrame

            _ ->
                Sub.none
        ]


applicationUrl historicSeconds =
    Url.Builder.crossOrigin
        "wss://isre1late.erictapen.name"
        [ "api", "ws", "delays" ]
        [ Url.Builder.int "historic" historicSeconds ]


init : () -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        defaultHistoricSeconds =
            3600 * 3

        defaultMode =
            Hour

        modeFromUrl =
            UP.parse urlParser url

        initModel =
            { navigationKey = key
            , mode = Maybe.withDefault defaultMode modeFromUrl
            , modeTransition = { touchState = Nothing, progress = 0 }
            , delayRecords = Dict.empty
            , errors = []
            , now = Nothing
            , timeZone = Nothing
            , historicSeconds = defaultHistoricSeconds
            , direction = Eastwards
            , distanceMatrix = initDistanceMatrix
            }
    in
    ( initModel
    , Cmd.batch
        [ rebuildSocket <| applicationUrl defaultHistoricSeconds
        , Task.perform CurrentTimeZone Time.here
        , case modeFromUrl of
            Just _ ->
                Cmd.none

            Nothing ->
                Browser.Navigation.pushUrl key <| buildUrl defaultMode
        ]
    )


{-| Place a train going inbetween two stations in the y axis of the entire diagram.
Result contains the y axis value (between 0 and 1), the direction the train
must be going in and wether it skips any stations on its path.
-}
trainPos : DistanceMatrix -> StationId -> StationId -> Float -> Maybe ( Float, Direction, Bool )
trainPos distanceMatrix from to percentageSegment =
    case Dict.get ( from, to ) distanceMatrix of
        Just { start, end, direction, skipsStations } ->
            Just
                ( case direction of
                    Eastwards ->
                        start + (end - start) * percentageSegment

                    Westwards ->
                        start - (start - end) * percentageSegment
                , direction
                , skipsStations
                )

        Nothing ->
            Nothing


{-| Get the y position of a station, e.g. for legends.
-}
stationPos : DistanceMatrix -> StationId -> Float
stationPos distanceMatrix sid =
    let
        magdeburgHbf =
            900550094
    in
    -- Magdeburg Hbf is the last one in the track, but distanceMatrix wouldn't
    -- contain a value for it, so we just hardcode it to 1
    if sid == magdeburgHbf then
        1

    else
        Maybe.withDefault -1 <| Maybe.map (\r -> r.start) <| Dict.get ( sid, magdeburgHbf ) distanceMatrix


yPosition : Float -> String
yPosition p =
    fromFloat (p * 100) ++ "%"


stationLegend : DistanceMatrix -> Direction -> List StationId -> List (Html Msg)
stationLegend distanceMatrix selectedDirection =
    map
        (\sid ->
            let
                sPos =
                    stationPos distanceMatrix sid
            in
            div
                [ style "top" <|
                    yPosition <|
                        case selectedDirection of
                            Westwards ->
                                sPos

                            Eastwards ->
                                1 - sPos
                , style "position" "absolute"
                , style "text-anchor" "right"
                , style "margin-top" "-0.5em"
                ]
                [ text <|
                    Maybe.withDefault "Unkown Station" <|
                        Maybe.map .shortName <|
                            Dict.get sid stationNames
                ]
        )


stationLines : DistanceMatrix -> List StationId -> List (Svg Msg)
stationLines distanceMatrix =
    map
        (\sid ->
            line
                [ x1 "100%"
                , x2 "0%"
                , y1 <| yPosition <| stationPos distanceMatrix sid
                , y2 <| yPosition <| stationPos distanceMatrix sid
                , stroke "#dddddd"
                , strokeWidth "0.2px"
                ]
                []
        )


posixToSec : Posix -> Int
posixToSec p =
    posixToMillis p // 1000


tripLines : DistanceMatrix -> Direction -> Int -> Dict TripId (List DelayRecord) -> Posix -> Svg Msg
tripLines distanceMatrix selectedDirection historicSeconds delayDict now =
    let
        tripD : Bool -> DelayRecord -> Maybe ( Float, Float )
        tripD secondPass { time, previousStation, nextStation, percentageSegment, delay } =
            case trainPos distanceMatrix previousStation nextStation percentageSegment of
                Just ( yPos, direction, skipsLines ) ->
                    if direction == selectedDirection then
                        Just
                            ( toFloat historicSeconds
                                - (toFloat <|
                                    posixToSec now
                                        - posixToSec time
                                        - (if secondPass then
                                            -- Apparently this is never < 0 anyway?
                                            max 0 delay

                                           else
                                            0
                                          )
                                  )
                            , 100 * yPos
                            )

                    else
                        Nothing

                _ ->
                    Nothing

        tripLine : ( TripId, List DelayRecord ) -> Svg Msg
        tripLine ( tripId, delayRecords ) =
            g
                [ SA.title tripId
                , SA.id tripId
                ]
                [ path
                    [ stroke "none"

                    -- red for delay
                    , fill "#e86f6f"
                    , d <|
                        "M "
                            ++ (String.join " L " <|
                                    map
                                        (\( x, y ) -> fromFloat x ++ " " ++ fromFloat y)
                                    <|
                                        filterMap identity <|
                                            List.concat
                                                [ map (tripD False) delayRecords
                                                , map (tripD True) <| List.reverse delayRecords
                                                ]
                               )
                    ]
                    []
                , path
                    [ stroke "black"
                    , fill "none"
                    , strokeWidth "1px"
                    , HA.attribute "vector-effect" "non-scaling-stroke"
                    , d <|
                        "M "
                            ++ (String.join " L " <|
                                    map
                                        (Tuple.mapBoth fromFloat fromFloat >> (\( x, y ) -> x ++ " " ++ y))
                                    <|
                                        filterMap identity <|
                                            map (tripD False) delayRecords
                               )
                    ]
                    []
                ]
    in
    g [] <| map tripLine <| Dict.toList delayDict


timeLegend : Int -> Time.Zone -> Posix -> Svg Msg
timeLegend historicSeconds tz now =
    let
        currentHourBegins =
            Time.toSecond tz now + Time.toMinute tz now * 60

        hourLine sec =
            line
                [ x1 <| fromInt sec
                , x2 <| fromInt sec
                , y1 "0%"
                , y2 "100%"
                , stroke "#dddddd"
                , strokeWidth "1px"
                , HA.attribute "vector-effect" "non-scaling-stroke"
                ]
                []
    in
    g [ SA.id "time-legend" ] <|
        map hourLine <|
            map (\i -> historicSeconds - currentHourBegins - i * 3600) <|
                List.range 0 (historicSeconds // 3600)


timeTextLegend : Int -> Time.Zone -> Posix -> Html Msg
timeTextLegend historicSeconds tz now =
    let
        currentHourBegins =
            Time.toSecond tz now + Time.toMinute tz now * 60

        hourText sec =
            div
                [ style "top" "0"
                , style "left" <|
                    (fromFloat <| 100 * (toFloat (historicSeconds - sec) / toFloat historicSeconds))
                        ++ "%"
                , style "position" "absolute"
                , style "transform" "translateX(-50%)"
                ]
                [ text <|
                    (fromInt <|
                        Time.toHour tz <|
                            Time.millisToPosix <|
                                1000
                                    * (posixToSec now - sec)
                    )
                        ++ ":00"
                ]
    in
    div [ id "time-text-legend" ] <|
        map hourText <|
            map (\i -> currentHourBegins + i * 3600) <|
                List.range 0 (historicSeconds // 3600)


modeH1 : Mode -> String
modeH1 mode =
    case mode of
        SingleTrip ->
            "Single trip"

        Hour ->
            "Hour"

        Day ->
            "Day"

        Week ->
            "Week"

        Year ->
            "Year"


view : Model -> Browser.Document Msg
view model =
    { title = "Is RE1 late?"
    , body =
        case ( model.timeZone, model.now ) of
            ( Just timeZone, Just now ) ->
                [ div
                    [ id "app"
                    , Touch.onStart (\event -> TouchMsg 0 Start <| touchCoordinates event)
                    , Touch.onMove (\event -> TouchMsg 0 Move <| touchCoordinates event)
                    , Touch.onEnd (\event -> TouchMsg 0 End <| touchCoordinates event)
                    , Touch.onCancel (\event -> TouchMsg 0 Cancel <| touchCoordinates event)
                    ]
                    [ h1 []
                        [ text <| modeH1 model.mode
                        , div [ style "font-weight" "100" ]
                            [ text <| " " ++ fromFloat model.modeTransition.progress ]
                        ]
                    , button
                        [ id "reverse-direction-button", onClick ToggleDirection ]
                        [ text "⮀" ]
                    , div [ id "row1" ]
                        [ svg
                            [ id "diagram"
                            , preserveAspectRatio "none"
                            , viewBox <| "0 0 " ++ fromInt model.historicSeconds ++ " 100"
                            ]
                            [ timeLegend model.historicSeconds timeZone now
                            , g [ SA.id "station-lines" ] <|
                                stationLines model.distanceMatrix <|
                                    map Tuple.first stations
                            , tripLines
                                model.distanceMatrix
                                model.direction
                                model.historicSeconds
                                model.delayRecords
                                now
                            ]
                        , div
                            [ class "station-legend" ]
                          <|
                            stationLegend model.distanceMatrix model.direction <|
                                map Tuple.first stations
                        ]
                    , div [ id "row2" ]
                        [ timeTextLegend model.historicSeconds timeZone now
                        , div [ class "station-legend" ] []
                        ]
                    ]
                ]

            _ ->
                [ div [ id "loading-screen" ]
                    [ Svg.Loaders.grid
                        [ Svg.Loaders.size 300, Svg.Loaders.color "#dddddd" ]
                    ]
                ]
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChange urlRequest ->
            case urlRequest of
                External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

                Internal url ->
                    case UP.parse urlParser url of
                        Just newMode ->
                            ( { model | mode = newMode }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RecvWebsocket jsonStr ->
            case decodeString decodeClientMsg jsonStr of
                Ok ( tripId, delay ) ->
                    ( { model
                        | delayRecords =
                            Dict.update tripId
                                (\maybeList ->
                                    Just <|
                                        delay
                                            :: Maybe.withDefault [] maybeList
                                )
                                model.delayRecords
                      }
                    , Cmd.none
                    )

                Err e ->
                    ( { model | errors = JD.errorToString e :: model.errors }, Cmd.none )

        Send ->
            ( model, sendMessage "" )

        CurrentTime now ->
            ( { model | now = Just now }, Cmd.none )

        CurrentTimeZone zone ->
            ( { model | timeZone = Just zone }, Cmd.none )

        ToggleDirection ->
            ( { model
                | direction =
                    case model.direction of
                        Westwards ->
                            Eastwards

                        Eastwards ->
                            Westwards
              }
            , Cmd.none
            )

        TouchMsg touchId touchType ( _, y ) ->
            let
                threshold =
                    50

                oldModeTransition =
                    model.modeTransition
            in
            case ( touchType, model.modeTransition.touchState ) of
                ( Start, Nothing ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState =
                                    Just
                                        { id = touchId
                                        , startingPos = y
                                        , currentPos = y
                                        , progressBeforeTouch = oldModeTransition.progress
                                        }
                            }
                      }
                    , Cmd.none
                    )

                ( Move, Just touchState ) ->
                    let
                        -- The length in pixels that we would require as a touch event for a full transition.
                        -- Note that the threshold would kick way sooner.
                        assumedScreenHeight =
                            800
                    in
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Just { touchState | currentPos = y }
                                , progress =
                                    touchState.progressBeforeTouch
                                        + ((touchState.startingPos - y) / assumedScreenHeight)
                            }
                      }
                    , Cmd.none
                    )

                ( End, Just touchState ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Nothing
                            }
                      }
                    , Cmd.none
                    )

                ( Cancel, Just touchState ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Nothing
                            }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AnimationFrame delta ->
            let
                oldModeTransition =
                    model.modeTransition

                oldProgress =
                    oldModeTransition.progress

                -- Time in ms it would take for a full progress to "cool down" to 0
                transitionDuration =
                    1000

                progressDelta =
                    delta / transitionDuration
            in
            ( { model
                | modeTransition =
                    { oldModeTransition
                        | progress =
                            if oldProgress > 0 then
                                max 0 (oldProgress - progressDelta)

                            else
                                min 0 (oldProgress + progressDelta)
                    }
              }
            , Cmd.none
            )


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlChange
        , onUrlChange = UrlChange << Browser.Internal
        }
