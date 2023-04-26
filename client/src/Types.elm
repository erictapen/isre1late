-- SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Types exposing (Delay, TripId)

import Json.Decode as J exposing (Decoder, decodeString, field, float, int, list, map2, map3, map5, string)
import Time exposing (Posix, millisToPosix)


type alias TripId =
    String


{-| TODO find a better name for this
-}
type alias Delay =
    { time : Posix
    , previousStation : String
    , nextStation : String
    , percentageSegment : Float
    , delay : Int
    }


decodeClientMsg : Decoder ( TripId, Delay )
decodeClientMsg =
    map2 Tuple.pair
        (field "id" string)
    <|
        map5 Delay
            (J.map ((*) 1000 >> millisToPosix) <| field "time" int)
            (field "previous_station" string)
            (field "next_station" string)
            (field "percentageSegment" float)
            (field "delay" int)
