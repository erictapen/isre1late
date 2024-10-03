-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.DiagramLines exposing (nowLine, stationLines, timeLines)

import Html.Attributes as HA
import List exposing (map)
import Model exposing (Direction(..), DistanceMatrix, Mode(..), stationPos, stations, trainPos)
import Msg exposing (Msg)
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg, text, text_)
import Svg.Attributes as SA
    exposing
        ( d
        , fill
        , fontSize
        , height
        , preserveAspectRatio
        , stroke
        , strokeDasharray
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
import Time exposing (Posix)
import Types exposing (DelayRecord, StationId, TripId, decodeDelayEvents, decodeDelayRecord)
import Utils
    exposing
        ( httpErrorToString
        , onTouch
        , percentageStr
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )


{-| The vertical lines in the diagram.
-}
timeLines : Mode -> Int -> Time.Zone -> Posix -> Svg Msg
timeLines mode historicSeconds tz now =
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


{-| The vertical dotted line in the diagram that indicates the current moment.
-}
nowLine : Mode -> Posix -> Svg Msg
nowLine mode now =
    let
        nowSec =
            posixToSec now
    in
    if mode == Hour then
        line
            [ x1 <| fromFloat <| posixSecToSvg nowSec
            , x2 <| fromFloat <| posixSecToSvg nowSec
            , y1 "0"
            , y2 "100"
            , stroke "#000000"
            , strokeWidth "1px"
            , strokeDasharray "10"
            , HA.attribute "vector-effect" "non-scaling-stroke"
            ]
            []

    else
        S.text ""


{-| The horizontal lines in the diagram.
-}
stationLines : Int -> Posix -> DistanceMatrix -> List (Svg Msg)
stationLines hisSeconds now distanceMatrix =
    let
        x1Pos =
            posixSecToSvg (posixToSec now - hisSeconds)

        -- We overdraw half an hour, so that the Hour view can show the future
        x2Pos =
            posixSecToSvg <| posixToSec now + 1800
    in
    map
        (\( sid, _ ) ->
            line
                [ x1 <| fromFloat x1Pos
                , x2 <| fromFloat x2Pos
                , y1 <| percentageStr <| stationPos distanceMatrix sid
                , y2 <| percentageStr <| stationPos distanceMatrix sid
                , stroke "#dddddd"
                , strokeWidth "0.2px"
                ]
                []
        )
        stations
