-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.TimeLegend exposing (view)

import Html as H exposing (Html, button, div, h1, p, text)
import Html.Attributes as HA exposing (class, id, style)
import List exposing (filterMap, head, indexedMap, map)
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg, text_)
import Time exposing (Posix, millisToPosix, posixToMillis)
import Utils
    exposing
        ( httpErrorToString
        , onTouch
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )


view : Int -> Time.Zone -> Posix -> Html Msg
view historicSeconds tz now =
    let
        stepSize =
            10 * 60

        currentStepBegins =
            remainderBy stepSize (Time.toSecond tz now + Time.toMinute tz now * 60)

        hourText sec =
            div
                [ style "top" "0"
                , style "left" <|
                    (fromFloat <| 100 * (toFloat (historicSeconds - sec) / toFloat historicSeconds))
                        ++ "%"
                , style "position" "absolute"
                , style "transform" "translateX(-50%)"
                ]
                -- TODO replace this with
                -- https://package.elm-lang.org/packages/CoderDennis/elm-time-format/latest/
                [ text <|
                    (fromInt <|
                        Time.toHour tz <|
                            Time.millisToPosix <|
                                1000
                                    * (posixToSec now - sec)
                    )
                        ++ ":"
                        ++ (String.padLeft 2 '0' <|
                                fromInt <|
                                    Time.toMinute tz <|
                                        Time.millisToPosix <|
                                            1000
                                                * (posixToSec now - sec)
                           )
                ]
    in
    div [ id "time-text-legend" ] <|
        map hourText <|
            map (\i -> currentStepBegins + i * stepSize) <|
                List.range 0 (historicSeconds // stepSize)
