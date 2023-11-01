-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.TimeLegend exposing (view)

import Html as H exposing (Html, button, div, h1, p, text)
import Html.Attributes as HA exposing (class, id, style)
import List exposing (filterMap, head, indexedMap, map)
import Model exposing (Mode(..))
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg, text_)
import Time exposing (Posix, millisToPosix, posixToMillis)
import Time.Format
import Time.Format.Config.Config_en_us
import Utils
    exposing
        ( httpErrorToString
        , onTouch
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )


view : Mode -> Int -> Time.Zone -> Posix -> Html Msg
view mode historicSeconds tz now =
    let
        -- in seconds
        stepSize =
            case mode of
                Hour ->
                    10 * 60

                Day ->
                    3 * 60 * 60

                Week ->
                    24 * 60 * 60

                _ ->
                    0

        secsSinceLastMark =
            remainderBy stepSize
                (Time.toSecond tz now + Time.toMinute tz now * 60 + Time.toHour tz now * 3600)

        formatString =
            case mode of
                Trip _ ->
                    ""

                Week ->
                    "%a"

                Hour ->
                    "%H:%M"

                Day ->
                    "%H"

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
                    Time.Format.format Time.Format.Config.Config_en_us.config formatString tz <|
                        millisToPosix <|
                            1000
                                * (posixToSec now - sec)
                ]
    in
    div [ id "time-text-legend" ] <|
        map hourText <|
            map (\i -> secsSinceLastMark + i * stepSize) <|
                List.range 0 (historicSeconds // stepSize)
