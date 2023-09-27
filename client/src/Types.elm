-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Types exposing (DelayEvent, DelayRecord, StationId, TripId, decodeDelayEvents, decodeDelayRecord)

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
import Json.Decode.Pipeline exposing (optional, required)
import Time exposing (Posix, millisToPosix)


type alias TripId =
    String


type alias StationId =
    Int


type alias DelayRecord =
    { time : Posix
    , previousStation : StationId
    , nextStation : StationId
    , percentageSegment : Float
    , delay : Int
    }


decodeDelayRecord : Decoder ( TripId, DelayRecord )
decodeDelayRecord =
    map2 Tuple.pair
        (field "trip_id" string)
    <|
        map5 DelayRecord
            (J.map ((*) 1000 >> millisToPosix) <| field "time" int)
            (field "previous_station" int)
            (field "next_station" int)
            (field "percentage_segment" float)
            (field "delay" int)


type alias DelayEvent =
    { from_id : Int
    , to_id : Int
    , trip_id : String
    , time : Int
    , duration : Int
    , previous_station : Int
    , next_station : Int
    , percentage_segment : Float
    , delay : Int
    }


decodeDelayEvents : Decoder (List DelayEvent)
decodeDelayEvents =
    list decodeDelayEvent


decodeDelayEvent : Decoder DelayEvent
decodeDelayEvent =
    J.succeed DelayEvent
        |> required "from_id" int
        |> required "to_id" int
        |> required "trip_id" string
        |> required "time" int
        |> required "duration" int
        |> required "previous_station" int
        |> required "next_station" int
        |> required "percentage_segment" float
        |> required "delay" int


type alias Stopover =
    { stationId : StationId
    , plannedArrival : Maybe Int
    , arrivalDelay : Int
    , plannedDeparture : Maybe Int
    , departureDelay : Int
    }


decodeTrip : Decoder (List Stopover)
decodeTrip =
    J.field "stopovers" <| J.list decodeStopover


decodeStopover : Decoder Stopover
decodeStopover =
    J.map5 Stopover
        (J.at [ "stop", "id" ] int)
        (maybe (field "plannedArrival" int))
        (J.map (Maybe.withDefault 0) (maybe (field "arrivalDelay" int)))
        (maybe (field "plannedDeparture" int))
        (J.map (Maybe.withDefault 0) (maybe (field "departureDelay" int)))
