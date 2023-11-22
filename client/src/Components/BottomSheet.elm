-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Components.BottomSheet exposing (view)

import Html exposing (button, div, h1, h2, header, text)
import Html.Attributes exposing (attribute, class, id, style)
import Html.Events exposing (onClick)
import Model exposing (InfoState, Mode(..))
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
        ]
        [ div [ class "overlay", onClick <| SetInfoState False ] []
        , div [ class "contents", style "height" <| fromFloat contentHeightPercent ++ "vh" ]
            [ header
                [ class "controls"
                ]
                [ div
                    [ class "draggable-area"
                    , onTouch
                        "touchstart"
                        (\event -> TouchMsgBottomSheet Start <| touchCoordinates event)
                    , onTouch
                        "mousedown"
                        (\event -> TouchMsgBottomSheet Start <| touchCoordinates event)
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
                    [ div [ class "draggable-thumb" ] []
                    ]
                ]
            , div [ class "body" ] <|
                case mode of
                    Hour ->
                        [ h2 [] [ text "Hour" ] ]

                    Day ->
                        [ h2 [] [ text "Day" ] ]

                    Week ->
                        [ h2 [] [ text "Week" ] ]

                    _ ->
                        [ text "Lorem ipsum" ]
            ]
        ]
