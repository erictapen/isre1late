-- SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (main)

import Browser exposing (Document)
import Dict exposing (Dict)
import Html exposing (div)
import Html.Attributes exposing (id, style)
import Json.Decode as JD exposing (decodeString)
import List exposing (head, map)
import String exposing (fromFloat)
import Svg as S exposing (Svg, g, line, path, svg)
import Svg.Attributes as SA exposing (d, fill, height, preserveAspectRatio, stroke, strokeWidth, viewBox, width, x, x1, x2, y, y1, y2)
import Time exposing (Posix)
import Types exposing (Delay, StationId, TripId, decodeClientMsg)


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


type Msg
    = Send
    | RecvWebsocket String


subscriptions : Model -> Sub Msg
subscriptions _ =
    messageReceiver RecvWebsocket


type alias Model =
    { delays : Dict TripId (List Delay)
    , errors : List String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { delays = Dict.empty, errors = [] }, Cmd.none )


stations : List ( StationId, String )
stations =
    [ ( 900311307, "Eisenhüttenstadt, Bahnhof" )
    , ( 900360000, "Frankfurt (Oder), Bahnhof" )
    , ( 900310001, "Fürstenwalde, Bahnhof" )
    , ( 900310002, "Hangelsberg, Bahnhof" )
    , ( 900310003, "Grünheide, Fangschleuse Bhf" )
    , ( 900310004, "S Erkner Bhf" )
    , ( 900120003, "S Ostkreuz Bhf (Berlin)" )
    , ( 900120005, "S Ostbahnhof (Berlin)" )
    , ( 900100003, "S+U Alexanderplatz Bhf (Berlin)" )
    , ( 900100001, "S+U Friedrichstr. Bhf (Berlin)" )
    , ( 900003201, "S+U Berlin Hauptbahnhof" )
    , ( 900023201, "S+U Zoologischer Garten Bhf (Berlin)" )
    , ( 900024101, "S Charlottenburg Bhf (Berlin)" )
    , ( 900053301, "S Wannsee Bhf (Berlin)" )
    , ( 900230999, "S Potsdam Hauptbahnhof" )
    , ( 900220009, "Werder (Havel), Bahnhof" )
    , ( 900275110, "Brandenburg, Hauptbahnhof" )
    , ( 900275719, "Brandenburg, Kirchmöser Bhf" )
    , ( 900220249, "Wusterwitz, Bahnhof" )
    , ( 900550073, "Genthin, Bahnhof" )
    , ( 900550078, "Güsen, Bahnhof" )
    , ( 900550062, "Burg (bei Magdeburg), Bahnhof" )
    , ( 900550255, "Magdeburg-Neustadt, Bahnhof" )
    , ( 900550094, "Magdeburg, Hauptbahnhof" )
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


{-| Position an element on the canvas, considering a margin.
Input is a value between 0 and 1.
-}
yPosition : Float -> String
yPosition p =
    let
        yMargin =
            10
    in
    fromFloat (yMargin + (p * (100 - 2 * yMargin))) ++ "%"


stationLegend : Float -> List StationId -> List (Svg Msg)
stationLegend cursor stationIds =
    case stationIds of
        sid1 :: sids ->
            g []
                [ S.text_
                    [ y <| yPosition <| cursor / overallTrackLength
                    , x "75%"
                    , SA.textAnchor "right"
                    , SA.dominantBaseline "middle"
                    ]
                    [ S.text <| Maybe.withDefault "Unkown Station" <| Dict.get sid1 stationNames ]
                , line
                    [ x1 "73%"
                    , x2 "0%"
                    , y1 <| yPosition <| cursor / overallTrackLength
                    , y2 <| yPosition <| cursor / overallTrackLength
                    , stroke "#dddddd"
                    , strokeWidth "1px"
                    ]
                    []
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


view : Model -> Document Msg
view model =
    { title = "Is RE1 late?"
    , body =
        [ div [ id "app" ]
            [ svg
                [ width "100%"
                , height "100vh"
                ]
                ([ svg
                    [ preserveAspectRatio "none"
                    , viewBox "0 0 100 100"
                    ]
                    [ path
                        [ x "10"
                        , y "10"
                        , stroke "black"
                        , fill "red"
                        , strokeWidth "1px"
                        , Html.Attributes.attribute "vector-effect" "non-scaling-stroke"
                        , d "M 10 10  L 20 40"
                        ]
                        []
                    ]
                 ]
                    ++ (stationLegend 0 <| map Tuple.first stations)
                )
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


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
