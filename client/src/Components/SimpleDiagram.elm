module Components.SimpleDiagram exposing (view)

import Dict exposing (Dict)
import Html.Attributes as HA exposing (class, id, style)
import List exposing (filterMap, head, indexedMap, map)
import Model exposing (Direction(..), DistanceMatrix, stationPos, stations, trainPos)
import Msg exposing (Msg(..), SwitchDirection(..), TouchMsgType(..))
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
import Time exposing (Posix, millisToPosix, posixToMillis)
import Types exposing (DelayRecord, StationId, TripId, decodeDelayEvents, decodeDelayRecord)
import Utils
    exposing
        ( httpErrorToString
        , onTouch
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )


{-| TODO move into Utils as percentStr
-}
yPosition : Float -> String
yPosition p =
    fromFloat (p * 100) ++ "%"


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
                    , fill "hsl(0, 72%, 67%)"
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
                                        (Tuple.mapBoth
                                            fromFloat
                                            fromFloat
                                            >> (\( x, y ) -> x ++ " " ++ y)
                                        )
                                    <|
                                        filterMap identity <|
                                            map (tripD False) delayRecords
                               )
                    ]
                    []
                ]
    in
    g [ id "trip-paths" ] <| map tripLine <| Dict.toList delayDict


view model now hisSeconds timeZone =
    [ timeLines hisSeconds timeZone now
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
