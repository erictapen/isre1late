module Components.InfoButton exposing (view)

import Html exposing (button, text)
import Html.Attributes exposing (id, style)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))


view infoState =
    let
        visible =
            infoState.visible
    in
    button
        [ id "info-button"
        , onClick <| SetInfoState <| not visible
        , style "font-weight" <|
            if visible then
                "800"

            else
                "500"
        ]
        [ text "ⓘ" ]
