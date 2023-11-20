-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.BottomSheet exposing (view)

import Html exposing (button, div, header, text)
import Html.Attributes exposing (attribute, class, id, style)
import Html.Events exposing (onClick)
import Model exposing (InfoState)
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat)
import Utils exposing (onTouch, touchCoordinates)


view infoState mode viewportHeight =
    let
        contentHeightPercent =
            100 - (100 * (infoState.dragPos / viewportHeight))
    in
    div
        [ id "sheet"
        , class "sheet"
        , attribute "aria-hidden"
            (if infoState.visible then
                "false"

             else
                "true"
            )
        , onTouch
            "touchmove"
            (\event -> TouchMsgBottomSheet Move <| touchCoordinates event)
        , onTouch
            "mousemove"
            (\event -> TouchMsgBottomSheet Move <| touchCoordinates event)
        , onTouch
            "touchend"
            (\event -> TouchMsgBottomSheet End <| touchCoordinates event)
        , onTouch
            "mouseup"
            (\event -> TouchMsgBottomSheet End <| touchCoordinates event)
        , onTouch
            "touchcancel"
            (\event -> TouchMsgBottomSheet Cancel <| touchCoordinates event)
        ]
        [ div [ class "overlay", onClick <| SetInfoState False ] []
        , div [ class "contents", style "height" <| fromFloat contentHeightPercent ++ "vh" ]
            [ header
                [ class "controls"
                , onTouch
                    "touchstart"
                    (\event -> TouchMsgBottomSheet Start <| touchCoordinates event)
                , onTouch
                    "mousedown"
                    (\event -> TouchMsgBottomSheet Start <| touchCoordinates event)
                ]
                [ div
                    [ class "draggable-area"
                    ]
                    [ div [ class "draggable-thumb" ] []
                    ]
                ]
            , div [ class "body" ] [ text "Lorem ipsum" ]
            ]
        ]
