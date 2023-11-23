-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.Title exposing (..)

import Char
import Html exposing (Html, div, h1, span, text)
import Html.Attributes exposing (id, style)
import List exposing (filterMap, map)
import Model exposing (Mode(..), modeString, nextMode, previousMode)
import Msg exposing (Msg)
import String exposing (fromFloat, fromInt)


thinsp =
    String.fromChar (Char.fromCode 8201)


view : Mode -> Float -> Html Msg
view currentMode progress =
    div [ id "title" ]
        [ h1
            []
            [ text "How late is "
            , span [ style "background" "#e2001a", style "color" "white" ]
                [ text <| thinsp ++ thinsp ++ "RE1" ++ thinsp ++ thinsp
                ]
            , text <| " this " ++ modeString currentMode ++ "?"
            ]
        ]
