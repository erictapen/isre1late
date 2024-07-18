-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.Diagram exposing (view)

import Components.MareyDiagram
import Html as H exposing (Html, button, div, h1, p, text)
import Html.Attributes as HA exposing (class, id, style)
import Model exposing (Direction(..), Mode(..), Model)
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
import Utils
    exposing
        ( httpErrorToString
        , onTouch
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )
import Week.View


view : Model -> Posix -> Int -> Time.Zone -> Html Msg
view model now hisSeconds timeZone =
    svg
        [ id "diagram"
        , preserveAspectRatio "none"
        , viewBox <|
            fromFloat
                (posixSecToSvg
                    (posixToSec now - hisSeconds)
                )
                ++ " 0 "
                ++ (fromFloat <| ((toFloat <| hisSeconds) + (if model.mode == Hour then 1800 else 0)) / posixToSvgQuotient)
                ++ " 100"
        ]
        (case model.mode of
            Hour ->
                Components.MareyDiagram.view model now hisSeconds timeZone

            Day ->
                Components.MareyDiagram.view model now hisSeconds timeZone

            Week ->
                Week.View.view hisSeconds model.distanceMatrix now <|
                    Maybe.map
                        (case model.direction of
                            Eastwards ->
                                Tuple.first

                            Westwards ->
                                Tuple.second
                        )
                    <|
                        model.delayEvents

            _ ->
                -- TODO make this visible
                [ text_ [ x "50%", y "50%" ] [ text "Not implemented" ] ]
        )
