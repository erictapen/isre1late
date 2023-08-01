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
        , historicSeconds
        , initDistanceMatrix
        , nextMode
        , previousMode
        , stationNames
        , stations
        , urlParser
        )
import Msg exposing (Msg(..), SwitchDirection(..), TouchMsgType(..))
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
import Time exposing (Posix, millisToPosix, posixToMillis)
import Types exposing (DelayRecord, StationId, TripId, decodeClientMsg)
import Url
import Url.Builder
import Url.Parser as UP
import Utils exposing (onTouch, touchCoordinates)


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


applicationUrl =
    Url.Builder.crossOrigin
        "wss://isre1late.erictapen.name"
        [ "api", "ws", "delays" ]
        [ Url.Builder.int "historic" <| 3600 * 24 ]


init : () -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    let
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
            , direction = Eastwards
            , distanceMatrix = initDistanceMatrix
            }
    in
    ( initModel
    , Cmd.batch
        [ rebuildSocket <| applicationUrl
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


stationLines : Float -> Float -> DistanceMatrix -> List StationId -> List (Svg Msg)
stationLines x1Pos x2Pos distanceMatrix =
    map
        (\sid ->
            line
                [ x1 <| fromFloat x1Pos
                , x2 <| fromFloat x2Pos
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


tripLines : DistanceMatrix -> Direction -> Int -> Dict TripId (List DelayRecord) -> Svg Msg
tripLines distanceMatrix selectedDirection historicSeconds delayDict =
    let
        -- An svg d segment for a given directon and delay record
        tripD : Bool -> DelayRecord -> Maybe ( Float, Float )
        tripD secondPass { time, previousStation, nextStation, percentageSegment, delay } =
            case trainPos distanceMatrix previousStation nextStation percentageSegment of
                Just ( yPos, direction, skipsLines ) ->
                    if direction == selectedDirection then
                        Just
                            ( posixSecToSvg <|
                                posixToSec time
                                    + (if secondPass then
                                        -- Apparently this is never < 0 anyway?
                                        max 0 delay

                                       else
                                        0
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
    g [ id "trip-paths" ] <| map tripLine <| Dict.toList delayDict


timeLegend : Int -> Time.Zone -> Posix -> Svg Msg
timeLegend historicSeconds tz now =
    let
        currentHourBegins =
            Time.toSecond tz now + Time.toMinute tz now * 60

        nowSec =
            posixToSec now

        hourLine sec =
            line
                [ x1 <| fromFloat <| posixSecToSvg sec
                , x2 <| fromFloat <| posixSecToSvg sec
                , y1 "0"
                , y2 "100"
                , stroke "#dddddd"
                , strokeWidth "1px"
                , HA.attribute "vector-effect" "non-scaling-stroke"
                ]
                []
    in
    g [ SA.id "time-legend" ] <|
        map hourLine <|
            map (\i -> nowSec - currentHourBegins - i * 3600) <|
                List.range 0 (historicSeconds // 3600)


timeTextLegend : Int -> Time.Zone -> Posix -> Html Msg
timeTextLegend historicSeconds tz now =
    let
        stepSize =
            10 * 60

        currentStepBegins =
            remainderBy stepSize (Time.toSecond tz now + Time.toMinute tz now * 60)

        hourText sec =
            div
                [ style "top" "0"
                , style "left" <|
                    (fromFloat <| 100 * (toFloat (historicSeconds - sec) / toFloat historicSeconds))
                        ++ "%"
                , style "position" "absolute"
                , style "transform" "translateX(-50%)"
                ]
                -- TODO replace this with
                -- https://package.elm-lang.org/packages/CoderDennis/elm-time-format/latest/
                [ text <|
                    (fromInt <|
                        Time.toHour tz <|
                            Time.millisToPosix <|
                                1000
                                    * (posixToSec now - sec)
                    )
                        ++ ":"
                        ++ (String.padLeft 2 '0' <|
                                fromInt <|
                                    Time.toMinute tz <|
                                        Time.millisToPosix <|
                                            1000
                                                * (posixToSec now - sec)
                           )
                ]
    in
    div [ id "time-text-legend" ] <|
        map hourText <|
            map (\i -> currentStepBegins + i * stepSize) <|
                List.range 0 (historicSeconds // stepSize)


modeString : Mode -> String
modeString mode =
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


viewTitle : Mode -> Float -> Html Msg
viewTitle currentMode progress =
    let
        -- Unfortunately a top value higher than 100% grows the document, even
        -- though position is set to absolute. So this is a hack to never
        -- display elements with a top value higher than this. We make elements
        -- progressively invisible to cover up this hack.
        maxPos =
            0.8

        top pos =
            fromFloat (100 * (0.01 + pos)) ++ "%"

        modeButton direction =
            button
                [ onClick <|
                    ModeSwitch direction
                , style "visibility" <|
                    if progress == 0 then
                        "visible"

                    else
                        "hidden"
                ]
                [ text <|
                    case direction of
                        NextMode ->
                            "🞂"

                        PreviousMode ->
                            "🞀"
                ]

        modeH1 ( maybeMode, posOffset ) =
            let
                pos =
                    0 - progress + posOffset
            in
            case ( maybeMode, pos < maxPos ) of
                ( Just mode, True ) ->
                    Just <|
                        h1
                            [ style "top" <| top pos
                            , style "opacity" <| fromFloat <| 1 - (abs pos * (1 / maxPos))
                            ]
                            [ modeButton PreviousMode
                            , text <| modeString mode
                            , modeButton NextMode
                            ]

                _ ->
                    Nothing
    in
    div [] <|
        filterMap modeH1
            [ ( previousMode currentMode, -1 )
            , ( Just currentMode, 0 )
            , ( nextMode currentMode, 1 )
            ]


{-| Some point in the past as Posix time. Apparently, SVG viewBox can't handle full posix numbers.
-}
somePointInThePast : Int
somePointInThePast =
    1688162400


posixToSvgQuotient =
    100000


{-| Turn a Posix sec into a position on the SVG canvas.
SVG viewBox can't handle even a year in seconds, so we move the comma.
Also we normalise by some point in the past.
-}
posixSecToSvg : Int -> Float
posixSecToSvg secs =
    toFloat (secs - somePointInThePast) / posixToSvgQuotient


view : Model -> Browser.Document Msg
view model =
    { title = "Is RE1 late?"
    , body =
        case ( model.timeZone, model.now ) of
            ( Just timeZone, Just now ) ->
                let
                    hisSeconds =
                        historicSeconds model
                in
                [ div
                    [ id "app"
                    ]
                    [ viewTitle model.mode model.modeTransition.progress
                    , button
                        [ id "reverse-direction-button", onClick ToggleDirection ]
                        [ text "⮀" ]
                    , div [ id "row1" ]
                        [ svg
                            [ id "diagram"
                            , preserveAspectRatio "none"
                            , viewBox <|
                                fromFloat
                                    (posixSecToSvg
                                        (posixToSec now - hisSeconds)
                                    )
                                    ++ " 0 "
                                    ++ (fromFloat <| (toFloat <| hisSeconds) / posixToSvgQuotient)
                                    ++ " 100"
                            ]
                            [ timeLegend hisSeconds timeZone now
                            , g [ SA.id "station-lines" ] <|
                                stationLines
                                    (posixSecToSvg (posixToSec now - hisSeconds))
                                    (posixSecToSvg (posixToSec now))
                                    model.distanceMatrix
                                <|
                                    map Tuple.first stations
                            , tripLines
                                model.distanceMatrix
                                model.direction
                                hisSeconds
                                model.delayRecords
                            ]
                        , div
                            [ class "station-legend"
                            , onTouch "touchstart" (\event -> TouchMsg 0 Start <| touchCoordinates event)
                            , onTouch "touchmove" (\event -> TouchMsg 0 Move <| touchCoordinates event)
                            , onTouch "touchend" (\event -> TouchMsg 0 End <| touchCoordinates event)
                            , onTouch "touchcancel" (\event -> TouchMsg 0 Cancel <| touchCoordinates event)
                            ]
                          <|
                            stationLegend model.distanceMatrix model.direction <|
                                map Tuple.first stations
                        ]
                    , div [ id "row2" ]
                        [ timeTextLegend hisSeconds timeZone now
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
                oldModeTransition =
                    model.modeTransition

                -- The length in pixels that we would require as a touch event for a full transition.
                -- This doesn't need to be exact, as it just defines how much the finger needs
                -- to travel.
                -- Note that the threshold would kick in way sooner.
                assumedScreenHeight =
                    800

                -- The absolute progress value above which we trigger a transition.
                threshold =
                    0.3

                progressDelta touchState =
                    (touchState.startingPos - y) / assumedScreenHeight

                newProgress touchState =
                    touchState.progressBeforeTouch + progressDelta touchState
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
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Just { touchState | currentPos = y }
                                , progress = newProgress touchState
                            }
                      }
                    , Cmd.none
                    )

                -- The gesture finished and we evaluate wether a transition is going to happen.
                ( End, Just touchState ) ->
                    let
                        nP =
                            newProgress touchState

                        ( transitionTriggered, newMode ) =
                            if abs nP > threshold then
                                case
                                    if nP > 0 then
                                        nextMode model.mode

                                    else
                                        previousMode model.mode
                                of
                                    Just nM ->
                                        ( True, nM )

                                    -- TODO figure out wether we want to move
                                    -- the element at all in this case. Could
                                    -- be that the moving h1 is confusing to
                                    -- the user, when no further transition is
                                    -- possible anyway.
                                    Nothing ->
                                        ( False, model.mode )

                            else
                                ( False, model.mode )
                    in
                    ( { model
                        | mode = newMode
                        , modeTransition =
                            { oldModeTransition
                                | touchState = Nothing
                                , progress =
                                    if transitionTriggered then
                                        if nP > 0 then
                                            nP - 1

                                        else
                                            nP + 1

                                    else
                                        nP
                            }
                      }
                    , if transitionTriggered then
                        Browser.Navigation.pushUrl model.navigationKey <| buildUrl newMode

                      else
                        Cmd.none
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

        ModeSwitch direction ->
            let
                ( maybeNewMode, newProgress ) =
                    case direction of
                        NextMode ->
                            ( nextMode model.mode, -1 )

                        PreviousMode ->
                            ( previousMode model.mode, 1 )
            in
            case maybeNewMode of
                Just newMode ->
                    ( { model
                        | mode = newMode
                        , modeTransition = { touchState = Nothing, progress = newProgress }
                      }
                    , Browser.Navigation.pushUrl model.navigationKey <| buildUrl newMode
                    )

                Nothing ->
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
