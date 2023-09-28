-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Trip.View exposing (view)

import Components.Title
import Dict exposing (Dict)
import Html exposing (Html, button, p, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)
import Http exposing (Error(..))
import Model exposing (Mode(..))
import Msg exposing (Msg(..))
import String exposing (fromInt)
import Types exposing (DelayRecord, Stopover, TripId)


view : TripId -> Result Http.Error (List Stopover) -> List (Html Msg)
view tripId selectedTripResult =
    [ button [ id "trip-close-button", onClick (ModeSwitch Hour 0) ] [ text "⨯" ]
    , Components.Title.view (Trip tripId) 0.0
    , p []
        [ case selectedTripResult of
            Ok [] ->
                text "Loading..."

            Ok selectedTrip ->
                text <| (fromInt <| List.length selectedTrip) ++ " loaded stopovers."

            Err (BadBody errMsg) ->
                text errMsg

            Err (BadStatus 404) ->
                p []
                    [ text "Trip ID not found"
                    ]

            Err _ ->
                text "Something went wrong."
        ]
    ]
