-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Tutorial exposing (view)

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
import Utils exposing (maybe, removeNothings)


view tutorialState distanceMatrix =
    [ img [ class "tutorial-image", src "/assets/tutorial1.svg" ] [] ]
