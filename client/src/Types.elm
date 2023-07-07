-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Types exposing (Delay, StationId, TripId, decodeClientMsg)

import Json.Decode as J
    exposing
        ( Decoder
        , decodeString
        , field
        , float
        , int
        , list
        , map2
        , map3
        , map5
        , maybe
        , string
        )
import Time exposing (Posix, millisToPosix)


type alias TripId =
    String


type alias StationId =
    Int


{-| TODO find a better name for this
-}
type alias Delay =
    { time : Posix
    , previousStation : StationId
    , nextStation : StationId
    , percentageSegment : Float
    , delay : Int
    }


decodeClientMsg : Decoder ( TripId, Delay )
decodeClientMsg =
    map2 Tuple.pair
        (field "trip_id" string)
    <|
        map5 Delay
            (J.map ((*) 1000 >> millisToPosix) <| field "time" int)
            (field "previous_station" int)
            (field "next_station" int)
            (field "percentage_segment" float)
            (field "delay" int)
