-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Trip.View exposing (view)

import Components.Title
import Dict exposing (Dict)
import Html exposing (Html, text)
import Model exposing (Mode(..))
import Msg exposing (Msg(..))
import Types exposing (DelayRecord, TripId)


view : TripId -> Dict TripId (List DelayRecord) -> List (Html Msg)
view tripId delayRecords =
    [ Components.Title.view (Trip tripId) 0.0
    , text <|
        if Dict.member tripId delayRecords then
            tripId

        else
            "Trip ID " ++ tripId ++ " not found."
    ]
