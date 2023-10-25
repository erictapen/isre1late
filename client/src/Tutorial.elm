-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Tutorial exposing (animationDuration, next, subscriptions, view)

import Browser.Events
import Html exposing (button, div, img, text)
import Html.Attributes exposing (class, id, src, style)
import Html.Events exposing (onClick)
import List exposing (filterMap, map, map2)
import Model exposing (DistanceMatrix, TutorialState(..), stationPos, stations)
import Msg exposing (Msg(..))
import String exposing (fromFloat)
import Svg as S exposing (animate, circle, g, path, svg)
import Svg.Attributes as SA
    exposing
        ( attributeName
        , cx
        , cy
        , d
        , dur
        , fill
        , from
        , preserveAspectRatio
        , r
        , repeatCount
        , stroke
        , strokeWidth
        , to
        , values
        , viewBox
        )
import Task
import Time
import Utils exposing (maybe, removeNothings)


orderTutorialState tutorialState =
    case tutorialState of
        Geographic ->
            1

        Location ->
            2

        Time ->
            3

        Delay ->
            4

        Finished ->
            5


previous tutorialState =
    case tutorialState of
        Geographic ->
            Geographic

        Location ->
            Geographic

        Time ->
            Location

        Delay ->
            Time

        Finished ->
            Finished


next tutorialState =
    case tutorialState of
        Geographic ->
            Location

        Location ->
            Time

        Time ->
            Delay

        Delay ->
            Finished

        Finished ->
            Finished


subscriptions tutorialState =
    if tutorialState /= Finished then
        Browser.Events.onAnimationFrameDelta TimerTick

    else
        Sub.none


tutorialImage tutorialState =
    case tutorialState of
        Geographic ->
            "/assets/tutorial1.svg"

        Location ->
            "/assets/tutorial2.svg"

        Time ->
            "/assets/tutorial3.svg"

        Delay ->
            "/assets/tutorial4.svg"

        _ ->
            ""


animationDuration tutorialState =
    case tutorialState of
        Geographic ->
            5000

        Location ->
            5000

        Time ->
            5000

        Delay ->
            5000

        Finished ->
            0


view tutorialState distanceMatrix =
    let
        progressClass progressElement =
            if orderTutorialState tutorialState < orderTutorialState progressElement then
                class "inactive"

            else if tutorialState == progressElement then
                class "active"

            else
                class "passed"
    in
    [ div [ class "tutorial-image-container" ] [ img [ class "tutorial-image", src <| tutorialImage tutorialState ] [] ]
    , div [ id "tutorial-progress-container" ]
        [ div
            [ class "tutorial-progress"
            , progressClass Geographic
            , style "animation-duration"
                ((fromFloat <| animationDuration tutorialState / 1000) ++ "s")
            ]
            []
        , div
            [ class "tutorial-progress"
            , progressClass Location
            , style "animation-duration"
                ((fromFloat <| animationDuration tutorialState / 1000) ++ "s")
            ]
            []
        , div
            [ class "tutorial-progress"
            , progressClass Time
            , style "animation-duration"
                ((fromFloat <| animationDuration tutorialState / 1000) ++ "s")
            ]
            []
        , div
            [ class "tutorial-progress"
            , progressClass Delay
            , style "animation-duration"
                ((fromFloat <| animationDuration tutorialState / 1000) ++ "s")
            ]
            []
        ]
    , div
        [ id "tutorial-button"
        , class "previous"
        , onClick <| SetTutorialState <| previous tutorialState
        ]
        []
    , div
        [ id "tutorial-button"
        , class "next"
        , onClick <| SetTutorialState <| next tutorialState
        ]
        []
    ]
