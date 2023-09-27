-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Trip.View exposing (view)

import Components.Title
import Dict exposing (Dict)
import Html exposing (Html, p, text)
import Http exposing (Error(..))
import Model exposing (Mode(..))
import Msg exposing (Msg(..))
import String exposing (fromInt)
import Types exposing (DelayRecord, Stopover, TripId)


view : TripId -> Result Http.Error (List Stopover) -> List (Html Msg)
view tripId selectedTripResult =
    [ Components.Title.view (Trip tripId) 0.0
    , p []
        [ case selectedTripResult of
            Ok [] ->
                text "Loading..."

            Ok selectedTrip ->
                text <| (fromInt <| List.length selectedTrip) ++ " loaded stopovers."

            Err err ->
                text <|
                    "Something went wrong"
                        ++ (case err of
                                BadBody errMsg ->
                                    errMsg

                                _ ->
                                    ""
                           )
        ]
    ]
