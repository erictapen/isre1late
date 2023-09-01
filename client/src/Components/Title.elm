-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.Title exposing (..)

import Html exposing (Html, div, h1, text)
import Html.Attributes exposing (style)
import List exposing (filterMap, map)
import Model exposing (Mode(..), nextMode, previousMode)
import Msg exposing (Msg)
import String exposing (fromFloat, fromInt)


modeString : Mode -> String
modeString mode =
    case mode of
        Trip _ ->
            "Trip"

        Hour ->
            "Hour"

        Day ->
            "Day"

        Week ->
            "Week"

        Year ->
            "Year"


view : Mode -> Float -> Html Msg
view currentMode progress =
    let
        -- Unfortunately a top value higher than 100% grows the document, even
        -- though position is set to absolute. So this is a hack to never
        -- display elements with a top value higher than this. We make elements
        -- progressively invisible to cover up this hack.
        maxPos =
            0.8

        top pos =
            fromFloat (100 * (0.01 + pos)) ++ "%"

        modeH1 ( maybeMode, posOffset ) =
            let
                pos =
                    0 - progress + posOffset
            in
            case ( maybeMode, pos < maxPos ) of
                ( Just mode, True ) ->
                    Just <|
                        h1
                            [ style "top" <| top pos
                            , style "left" "3%"
                            , style "opacity" <| fromFloat <| 1 - (abs pos * (1 / maxPos))
                            ]
                            [ text <| "Is RE1 late this " ++ modeString mode ++ "?"
                            ]

                _ ->
                    Nothing
    in
    div [] <|
        filterMap modeH1
            [ ( previousMode currentMode, -1 )
            , ( Just currentMode, 0 )
            , ( nextMode currentMode, 1 )
            ]
