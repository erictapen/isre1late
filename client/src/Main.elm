-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (initDistanceMatrix, main, stationPos, trainPos)

import Browser exposing (UrlRequest(..))
import Browser.Events
import Browser.Navigation
import Dict exposing (Dict)
import Html as H exposing (Html, button, div, text)
import Html.Attributes as HA exposing (class, id, style)
import Html.Events exposing (onClick)
import Json.Decode as JD exposing (decodeString)
import List exposing (filterMap, head, indexedMap, map)
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


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port rebuildSocket : String -> Cmd msg


type Msg
    = UrlChange UrlRequest
    | Send
    | RecvWebsocket String
    | CurrentTime Posix
    | CurrentTimeZone Time.Zone
    | ToggleDirection


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ messageReceiver RecvWebsocket

        -- TODO synchronise this with RecvWebsocket after the loading state is implemented
        , Time.every 1000 CurrentTime
        ]


type Direction
    = Westwards
    | Eastwards


type alias DistanceMatrix =
    Dict
        ( StationId, StationId )
        { start : Float
        , end : Float
        , direction : Direction
        , skipsStations : Bool
        }


type Mode
    = SingleTrip
    | Hour
    | Day
    | Week
    | Year


type alias Model =
    { navigationKey : Browser.Navigation.Key
    , mode : Mode
    , delayRecords : Dict TripId (List DelayRecord)
    , errors : List String
    , now : Maybe Posix
    , timeZone : Maybe Time.Zone
    , historicSeconds : Int
    , direction : Direction
    , distanceMatrix : DistanceMatrix
    }


urlParser : UP.Parser (Mode -> a) a
urlParser =
    UP.oneOf
        [ UP.map SingleTrip (UP.s "trip")
        , UP.map Hour (UP.s "hour")
        , UP.map Day (UP.s "day")
        , UP.map Week (UP.s "week")
        , UP.map Year (UP.s "year")
        ]


{-| A matrix that contains the positions for every combination of stations,
along with the direction the two stations are facing and wether they would
skip any stations on the RE1 track.

This scales quadratically, so be careful with the number of stations!

-}
initDistanceMatrix : DistanceMatrix
initDistanceMatrix =
    let
        -- We subtract one, because we place by zero-led index
        stationsCount =
            toFloat <| List.length stations - 1

        stationId =
            Tuple.first

        oneToNDistances direction cursorIndex ( cursorSid, _ ) =
            indexedMap
                (\i ( sid, _ ) ->
                    if cursorIndex >= i then
                        Nothing

                    else
                        Just
                            ( ( cursorSid, sid )
                            , { start = toFloat cursorIndex / stationsCount
                              , end = toFloat i / stationsCount
                              , direction = direction
                              , skipsStations =
                                    if i > cursorIndex + 1 then
                                        True

                                    else
                                        False
                              }
                            )
                )
            <|
                case direction of
                    Westwards ->
                        stations

                    Eastwards ->
                        List.reverse stations
    in
    Dict.fromList <|
        filterMap identity <|
            List.concat <|
                indexedMap (oneToNDistances Westwards) stations
                    ++ (indexedMap (oneToNDistances Eastwards) <| List.reverse stations)


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

        modeFromUrl =
            case UP.parse urlParser url of
                Just newMode ->
                    newMode

                Nothing ->
                    Hour

        initModel =
            { navigationKey = key
            , mode = modeFromUrl
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
        ]
    )


type alias StationInfo =
    { name : String
    , shortName : String
    }


stations : List ( StationId, StationInfo )
stations =
    [ ( 900470000
      , { name = "Cottbus, Hauptbahnhof"
        , shortName = "Cottbus"
        }
      )
    , ( 900445593
      , { name = "Guben, Bahnhof"
        , shortName = "Guben"
        }
      )
    , ( 900311307
      , { name = "Eisenhüttenstadt, Bahnhof"
        , shortName = "Eisenhüttenstadt"
        }
      )
    , ( 900360000
      , { name = "Frankfurt (Oder), Bahnhof"
        , shortName = "Frankfurt (Oder)"
        }
      )
    , ( 900360004
      , { name = "Frankfurt (Oder), Rosengarten Bhf"
        , shortName = "Rosengarten"
        }
      )
    , ( 900310008
      , { name = "Pillgram, Bahnhof"
        , shortName = "Pillgram"
        }
      )
    , ( 900310007
      , { name = "Jacobsdorf (Mark), Bahnhof"
        , shortName = "Jacobsdorf"
        }
      )
    , ( 900310006
      , { name = "Briesen (Mark), Bahnhof"
        , shortName = "Briesen"
        }
      )
    , ( 900310005
      , { name = "Berkenbrück (LOS), Bahnhof"
        , shortName = "Berkenbrück"
        }
      )
    , ( 900310001
      , { name = "Fürstenwalde, Bahnhof"
        , shortName = "Fürstenwalde"
        }
      )
    , ( 900310002
      , { name = "Hangelsberg, Bahnhof"
        , shortName = "Hangelsberg"
        }
      )
    , ( 900310003
      , { name = "Grünheide, Fangschleuse Bhf"
        , shortName = "Fangschleuse"
        }
      )
    , ( 900310004
      , { name = "S Erkner Bhf"
        , shortName = "Erkner "
        }
      )
    , ( 900120003
      , { name = "S Ostkreuz Bhf (Berlin)"
        , shortName = "Ostkreuz"
        }
      )
    , ( 900120005
      , { name = "S Ostbahnhof (Berlin)"
        , shortName = "Ostbahnhof"
        }
      )
    , ( 900100003
      , { name = "S+U Alexanderplatz Bhf (Berlin)"
        , shortName = "Alexanderplatz"
        }
      )
    , ( 900100001
      , { name = "S+U Friedrichstr. Bhf (Berlin)"
        , shortName = "Friedrichstr."
        }
      )
    , ( 900003201
      , { name = "S+U Berlin Hauptbahnhof"
        , shortName = "Berlin Hbf"
        }
      )
    , ( 900023201
      , { name = "S+U Zoologischer Garten Bhf (Berlin)"
        , shortName = "Zoologischer Garten"
        }
      )
    , ( 900024101
      , { name = "S Charlottenburg Bhf (Berlin)"
        , shortName = "Charlottenburg"
        }
      )
    , ( 900053301
      , { name = "S Wannsee Bhf (Berlin)"
        , shortName = "Wannsee"
        }
      )
    , ( 900230999
      , { name = "S Potsdam Hauptbahnhof"
        , shortName = "Potsdam"
        }
      )
    , ( 900230006
      , { name = "Potsdam, Charlottenhof Bhf"
        , shortName = "Charlottenhof"
        }
      )
    , ( 900230007
      , { name = "Potsdam, Park Sanssouci Bhf"
        , shortName = "Park Sanssouci"
        }
      )
    , ( 900220009
      , { name = "Werder (Havel), Bahnhof"
        , shortName = "Werder (Havel)"
        }
      )
    , ( 900220699
      , { name = "Groß Kreutz, Bahnhof"
        , shortName = "Groß Kreutz"
        }
      )
    , ( 900220182
      , { name = "Götz, Bahnhof"
        , shortName = "Götz"
        }
      )
    , ( 900275110
      , { name = "Brandenburg, Hauptbahnhof"
        , shortName = "Brandenburg"
        }
      )
    , ( 900275719
      , { name = "Brandenburg, Kirchmöser Bhf"
        , shortName = "Kirchmöser"
        }
      )
    , ( 900220249
      , { name = "Wusterwitz, Bahnhof"
        , shortName = "Wusterwitz"
        }
      )
    , ( 900550073
      , { name = "Genthin, Bahnhof"
        , shortName = "Genthin"
        }
      )
    , ( 900550078
      , { name = "Güsen, Bahnhof"
        , shortName = "Güsen"
        }
      )
    , ( 900550062
      , { name = "Burg (bei Magdeburg), Bahnhof"
        , shortName = "Burg (bei Magdeburg)"
        }
      )
    , ( 900550255
      , { name = "Magdeburg-Neustadt, Bahnhof"
        , shortName = "Magdeburg-Neustadt"
        }
      )
    , ( 900550094
      , { name = "Magdeburg, Hauptbahnhof"
        , shortName = "Magdeburg"
        }
      )
    ]


stationNames =
    Dict.fromList stations


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


view : Model -> Browser.Document Msg
view model =
    { title = "Is RE1 late?"
    , body =
        case ( model.timeZone, model.now ) of
            ( Just timeZone, Just now ) ->
                [ div [ id "app" ]
                    [ button
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


buildUrl : Mode -> String
buildUrl mode =
    "/"
        ++ (case mode of
                SingleTrip ->
                    "trip"

                Hour ->
                    "hour"

                Day ->
                    "day"

                Week ->
                    "week"

                Year ->
                    "year"
           )


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
                            , Browser.Navigation.pushUrl model.navigationKey <| buildUrl model.mode
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
