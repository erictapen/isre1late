module Week.View exposing (view)

import Dict
import Html exposing (Html, div)
import List exposing (map)
import Model exposing (DelayEventsMatrix, DelayPerSecond)
import Msg exposing (Msg(..))
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, rect)
import Svg.Attributes as SA exposing (fill, height, stroke, title, width, x, y)
import Time exposing (Posix)
import Utils exposing (posixSecToSvg, posixToSec, posixToSvgQuotient)
import Week.Constants


maxDelayPerSecondPerTile =
    -- TODO make this dependent on tile size
    1500000


colorValue i =
    let
        lightness =
            max 0 <| min 100 <| round <| 50 + 50 * (1 - (toFloat i / maxDelayPerSecondPerTile))
    in
    "hsl(0, 100%, " ++ fromInt lightness ++ "%)"


heatMapTile : Posix -> ( ( Int, Int ), DelayPerSecond ) -> Svg Msg
heatMapTile now ( ( column, row ), delayPerSecond ) =
    rect
        [ x <| fromFloat <| posixSecToSvg <| posixToSec now - column * Week.Constants.secondsPerColumn
        , y <| fromFloat <| (*) 100 <| toFloat row / toFloat Week.Constants.rows
        , width <| fromFloat <| toFloat Week.Constants.secondsPerColumn / posixToSvgQuotient
        , height <| fromFloat <| (*) 100 <| 1 / toFloat Week.Constants.rows
        , stroke "none"
        , fill <| colorValue delayPerSecond
        , title <| fromInt <| delayPerSecond
        ]
        []


view : Maybe Posix -> Maybe DelayEventsMatrix -> List (Svg Msg)
view maybeNow mM =
    case ( mM, maybeNow ) of
        ( Just m, Just now ) ->
            map (heatMapTile now) <| Dict.toList m

        _ ->
            []
