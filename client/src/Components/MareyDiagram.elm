-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.MareyDiagram exposing (view)

import Components.DiagramLines exposing (nowLine, stationLines, timeLines)
import Dict exposing (Dict)
import Html.Attributes as HA exposing (class, id, style)
import List exposing (filterMap, head, indexedMap, map)
import Maybe exposing (withDefault)
import Model exposing (Direction(..), DistanceMatrix, Mode(..), Model, stationPos, stations, trainPos)
import Msg exposing (Msg(..), TouchMsgType(..))
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
import Svg.Events
import Time exposing (Posix, millisToPosix, posixToMillis)
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


tripLines : Mode -> DistanceMatrix -> Direction -> Int -> Dict TripId (List DelayRecord) -> Svg Msg
tripLines mode distanceMatrix selectedDirection historicSeconds delayDict =
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
            let
                intendedPath =
                    "M"
                        ++ (String.join " L" <|
                                map
                                    (Tuple.mapBoth
                                        fromFloat
                                        fromFloat
                                        >> (\( x, y ) -> x ++ "," ++ y)
                                    )
                                <|
                                    filterMap identity <|
                                        map (tripD False) delayRecords
                           )
            in
            g
                [ SA.title tripId
                , SA.id tripId
                ]
                ([ -- The red area for delay
                   path
                    [ stroke "none"

                    -- red for delay
                    , fill "hsl(0, 72%, 67%)"
                    , d <|
                        "M"
                            ++ (String.join " L" <|
                                    map
                                        (\( x, y ) -> fromFloat x ++ "," ++ fromFloat y)
                                    <|
                                        filterMap identity <|
                                            List.concat
                                                [ map (tripD False) delayRecords
                                                , map (tripD True) <| List.reverse delayRecords
                                                ]
                               )
                    ]
                    []

                 -- black stroke for the intended time
                 , path
                    [ stroke "black"
                    , fill "none"
                    , strokeWidth "1px"
                    , HA.attribute "vector-effect" "non-scaling-stroke"
                    , d intendedPath
                    ]
                    []

                 -- invisible stroke for clickable area
                 ]
                    ++ (if mode == Hour then
                            [ path
                                [ stroke "#00000000"
                                , fill "none"
                                , strokeWidth "30px"
                                , HA.attribute "vector-effect" "non-scaling-stroke"
                                , d intendedPath
                                ]
                                []
                            ]

                        else
                            []
                       )
                )
    in
    g [ id "trip-paths" ] <| map tripLine <| Dict.toList delayDict


view : Model -> Posix -> Int -> Time.Zone -> List (Svg Msg)
view model now hisSeconds timeZone =
    [ nowLine model.mode now
    , timeLines model.mode hisSeconds timeZone now
    , g [ SA.id "station-lines" ] <|
        stationLines
            hisSeconds
            now
            model.distanceMatrix
    , tripLines
        model.mode
        model.distanceMatrix
        model.direction
        hisSeconds
        model.delayRecords
    ]
