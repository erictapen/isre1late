-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (main)

import Browser exposing (Document)
import Dict exposing (Dict)
import Html as H exposing (Html, div, text)
import Html.Attributes as HA exposing (class, id, style)
import Json.Decode as JD exposing (decodeString)
import List exposing (filterMap, head, map)
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
import Types exposing (Delay, StationId, TripId, decodeClientMsg)
import Url
import Url.Builder


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port rebuildSocket : String -> Cmd msg


type Msg
    = Send
    | RecvWebsocket String
    | CurrentTime Posix
    | CurrentTimeZone Time.Zone


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ messageReceiver RecvWebsocket

        -- TODO synchronise this with RecvWebsocket after the loading state is implemented
        , Time.every 1000 CurrentTime
        ]


type alias Model =
    { delays : Dict TripId (List Delay)
    , errors : List String
    , now : Maybe Posix
    , timeZone : Maybe Time.Zone
    , historicSeconds : Int
    }


applicationUrl historicSeconds =
    Url.Builder.crossOrigin
        "wss://isre1late.erictapen.name"
        [ "api", "delays" ]
        [ Url.Builder.int "historic" historicSeconds ]


init : () -> ( Model, Cmd Msg )
init _ =
    let
        defaultHistoricSeconds =
            3600 * 3
    in
    ( { delays = Dict.empty
      , errors = []
      , now = Nothing
      , timeZone = Nothing
      , historicSeconds = defaultHistoricSeconds
      }
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
    [ ( 900311307
      , { name = "Eisenhüttenstadt, Bahnhof"
        , shortName = "Eisenhüttenstadt"
        }
      )
    , ( 900360000
      , { name = "Frankfurt (Oder), Bahnhof"
        , shortName = "Frankfurt (Oder)"
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
    , ( 900220009
      , { name = "Werder (Havel), Bahnhof"
        , shortName = "Werder (Havel)"
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


{-| Calculate the distance between two station ids. None if it's impossible to
calculate.
-}
distance : StationId -> StationId -> Maybe Float
distance station1 station2 =
    case ( station1, station2 ) of
        ( 900311307, 900360000 ) ->
            Just 1

        ( 900360000, 900310001 ) ->
            Just 1

        ( 900310001, 900310002 ) ->
            Just 1

        ( 900310002, 900310003 ) ->
            Just 1

        ( 900310003, 900310004 ) ->
            Just 1

        ( 900310004, 900120003 ) ->
            Just 1

        ( 900120003, 900120005 ) ->
            Just 1

        ( 900120005, 900100003 ) ->
            Just 1

        ( 900100003, 900100001 ) ->
            Just 1

        ( 900100001, 900003201 ) ->
            Just 1

        ( 900003201, 900023201 ) ->
            Just 1

        ( 900023201, 900024101 ) ->
            Just 1

        ( 900024101, 900053301 ) ->
            Just 1

        ( 900053301, 900230999 ) ->
            Just 1

        ( 900230999, 900220009 ) ->
            Just 1

        ( 900220009, 900275110 ) ->
            Just 1

        ( 900275110, 900275719 ) ->
            Just 1

        ( 900275719, 900220249 ) ->
            Just 1

        ( 900220249, 900550073 ) ->
            Just 1

        ( 900550073, 900550078 ) ->
            Just 1

        ( 900550078, 900550062 ) ->
            Just 1

        ( 900550062, 900550255 ) ->
            Just 1

        ( 900550255, 900550094 ) ->
            Just 1

        _ ->
            Nothing


stationPos : StationId -> Float
stationPos sid =
    case sid of
        900311307 ->
            0 / 23

        900360000 ->
            1 / 23

        900310001 ->
            2 / 23

        900310002 ->
            3 / 23

        900310003 ->
            4 / 23

        900310004 ->
            5 / 23

        900120003 ->
            6 / 23

        900120005 ->
            7 / 23

        900100003 ->
            8 / 23

        900100001 ->
            9 / 23

        900003201 ->
            10 / 23

        900023201 ->
            11 / 23

        900024101 ->
            12 / 23

        900053301 ->
            13 / 23

        900230999 ->
            14 / 23

        900220009 ->
            15 / 23

        900275110 ->
            16 / 23

        900275719 ->
            17 / 23

        900220249 ->
            18 / 23

        900550073 ->
            19 / 23

        900550078 ->
            20 / 23

        900550062 ->
            21 / 23

        900550255 ->
            22 / 23

        900550094 ->
            23 / 23

        _ ->
            0


overallTrackLength : Float
overallTrackLength =
    let
        trackStep : List StationId -> Float
        trackStep stationIds =
            case stationIds of
                s1 :: s2 :: sis ->
                    Maybe.withDefault 0 (distance s1 s2) + trackStep (s2 :: sis)

                _ ->
                    0
    in
    trackStep <| map Tuple.first stations


yPosition : Float -> String
yPosition p =
    fromFloat (p * 100) ++ "%"


stationLegend : Float -> List StationId -> List (Html Msg)
stationLegend cursor stationIds =
    case stationIds of
        sid1 :: sids ->
            div
                [ style "top" <| yPosition <| cursor / overallTrackLength
                , style "position" "absolute"
                , style "text-anchor" "right"
                , style "margin-top" "-0.5em"
                ]
                [ text <|
                    Maybe.withDefault "Unkown Station" <|
                        Maybe.map .shortName <|
                            Dict.get sid1 stationNames
                ]
                :: stationLegend
                    (cursor
                        + (Maybe.withDefault 0 <|
                            Maybe.andThen (distance sid1) <|
                                head sids
                          )
                    )
                    sids

        _ ->
            []


stationLines : Float -> List StationId -> List (Svg Msg)
stationLines cursor stationIds =
    case stationIds of
        sid1 :: sids ->
            line
                [ x1 "100%"
                , x2 "0%"
                , y1 <| yPosition <| cursor / overallTrackLength
                , y2 <| yPosition <| cursor / overallTrackLength
                , stroke "#dddddd"
                , strokeWidth "0.2px"
                ]
                []
                :: stationLines
                    (cursor
                        + (Maybe.withDefault 0 <|
                            Maybe.andThen (distance sid1) <|
                                head sids
                          )
                    )
                    sids

        _ ->
            []


posixToSec : Posix -> Int
posixToSec p =
    posixToMillis p // 1000


{-| Wether two stations are ordered from west to east
-}
westwards s1 s2 =
    case distance s1 s2 of
        Just _ ->
            True

        Nothing ->
            False


tripLines : Int -> Dict TripId (List Delay) -> Posix -> Svg Msg
tripLines historicSeconds delayDict now =
    let
        tripD : Bool -> Delay -> Maybe ( Float, Float )
        tripD secondPass { time, previousStation, nextStation, percentageSegment, delay } =
            case ( previousStation, nextStation ) of
                ( Just pS, Just nS ) ->
                    if westwards pS nS then
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
                            , 100 * (stationPos pS + (percentageSegment / overallTrackLength))
                            )

                    else
                        Nothing

                _ ->
                    Nothing

        tripLine : ( TripId, List Delay ) -> Svg Msg
        tripLine ( tripId, delays ) =
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
                                                [ map (tripD False) delays
                                                , map (tripD True) <| List.reverse delays
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
                                            map (tripD False) delays
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


view : Model -> Document Msg
view model =
    { title = "Is RE1 late?"
    , body =
        case ( model.timeZone, model.now ) of
            ( Just timeZone, Just now ) ->
                [ div [ id "app" ]
                    [ div [ id "row1" ]
                        [ svg
                            [ id "diagram"
                            , preserveAspectRatio "none"
                            , viewBox <| "0 0 " ++ fromInt model.historicSeconds ++ " 100"
                            ]
                            [ timeLegend model.historicSeconds timeZone now
                            , g [ SA.id "station-lines" ] <| stationLines 0 <| map Tuple.first stations
                            , tripLines model.historicSeconds model.delays now
                            ]
                        , div [ class "station-legend" ] <| stationLegend 0 <| map Tuple.first stations
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
        RecvWebsocket jsonStr ->
            case decodeString decodeClientMsg jsonStr of
                Ok ( tripId, delay ) ->
                    ( { model
                        | delays =
                            Dict.update tripId
                                (\maybeList ->
                                    Just <|
                                        delay
                                            :: Maybe.withDefault [] maybeList
                                )
                                model.delays
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


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
