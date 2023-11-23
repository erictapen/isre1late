-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.Menu exposing (view)

import Html exposing (button, div, text)
import Html.Attributes exposing (class, style)
import Html.Events exposing (onClick)
import Model exposing (Mode(..), modeString, nextMode, previousMode)
import Msg exposing (Msg(..))


wrapButton button label =
    div [ class "menu-container" ]
        [ button
        , div [ class "menu-button-label" ] [ text label ]
        ]


greyedOutButton str =
    wrapButton
        (button
            [ class "menu-button", style "pointer-events" "none", style "opacity" "0.2" ]
            [ text str ]
        )
        ""


modeButton m currentMode =
    wrapButton
        (button
            [ class "menu-button"
            , onClick (ModeSwitch m 1)
            , style "font-weight" <|
                if m == currentMode then
                    "800"

                else
                    "500"
            ]
            [ text <| modeString m ]
        )
        ""


view mode =
    [ modeButton Week mode
    , modeButton Day mode
    , modeButton Hour mode
    , wrapButton
        (button
            [ class "menu-button", onClick ToggleDirection ]
            [ text "⇅" ]
        )
        "Direction"
    ]
