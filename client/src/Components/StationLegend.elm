-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.StationLegend exposing (view)

import Dict
import Html exposing (Html, div, text)
import Html.Attributes exposing (class, style)
import List exposing (map)
import Model exposing (Direction(..), DistanceMatrix, stationNames, stationPos, stations)
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat, fromInt)
import Types exposing (StationId)
import Utils exposing (onTouch, percentageStr, touchCoordinates)


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
                    percentageStr <|
                        case selectedDirection of
                            Westwards ->
                                sPos

                            Eastwards ->
                                1 - sPos
                , style "position" "absolute"
                , style "text-anchor" "right"
                , style "margin-top" "-0.5em"
                , style "font-weight" <|
                    if
                        Maybe.withDefault False <|
                            Maybe.map .important <|
                                Dict.get sid stationNames
                    then
                        "500"

                    else
                        "300"
                ]
                [ text <|
                    Maybe.withDefault "Unkown Station" <|
                        Maybe.map .shortName <|
                            Dict.get sid stationNames
                ]
        )


view distanceMatrix direction =
    div
        [ class "station-legend"
        , onTouch "touchstart" (\event -> TouchMsgTitle 0 Start <| touchCoordinates event)
        , onTouch "touchmove" (\event -> TouchMsgTitle 0 Move <| touchCoordinates event)
        , onTouch "touchend" (\event -> TouchMsgTitle 0 End <| touchCoordinates event)
        , onTouch "touchcancel" (\event -> TouchMsgTitle 0 Cancel <| touchCoordinates event)
        ]
    <|
        stationLegend distanceMatrix direction <|
            map Tuple.first stations
