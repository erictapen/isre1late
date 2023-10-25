-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.Menu exposing (view)

import Html exposing (button, div, text)
import Html.Attributes exposing (class, style)
import Html.Events exposing (onClick)
import Model exposing (Mode(..), nextMode, previousMode)
import Msg exposing (Msg(..))


wrapButton button =
    div [ class "menu-container" ]
        [ button ]


greyedOutButton str =
    wrapButton <|
        button
            [ class "menu-button", style "pointer-events" "none", style "opacity" "0.5" ]
            [ text str ]


view mode =
    [ greyedOutButton "ⓘ"
    , case previousMode mode of
        Just m ->
            wrapButton <|
                button
                    [ class "menu-button", onClick (ModeSwitch m 1) ]
                    [ text "+" ]

        Nothing ->
            greyedOutButton "+"
    , case nextMode mode of
        Just m ->
            wrapButton <|
                button
                    [ class "menu-button", onClick (ModeSwitch m -1) ]
                    [ text "−" ]

        Nothing ->
            greyedOutButton "−"
    , wrapButton <|
        button
            [ class "menu-button", onClick ToggleDirection ]
            [ text "⮀" ]
    ]
