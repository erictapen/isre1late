-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.DiagramLines exposing (stationLines, timeLines)

import Html.Attributes as HA
import List exposing (map)
import Model exposing (Direction(..), DistanceMatrix, Mode(..), stationPos, stations, trainPos)
import Msg exposing (Msg)
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg, text_)
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
timeLines : Int -> Time.Zone -> Posix -> Svg Msg
timeLines historicSeconds tz now =
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


{-| The horizontal lines in the diagram.
-}
stationLines : Float -> Float -> DistanceMatrix -> List StationId -> List (Svg Msg)
stationLines x1Pos x2Pos distanceMatrix =
    map
        (\sid ->
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
