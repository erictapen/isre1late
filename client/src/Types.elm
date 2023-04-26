module Types exposing (Delay, TripId)

import Time exposing (Posix, millisToPosix)

import Json.Decode as J exposing ( Decoder, decodeString, field, int, list, map2, map3, map5, string, float)

type alias TripId =
    String

type alias Delay =
    { time : Posix
    , previousStation : String
    , nextStation : String
    , percentageSegment : Float
    , delay : Int
    }


decodeClientMsg : Decoder (Delay)
decodeClientMsg =
    map5 Delay
        (J.map millisToPosix <| field "time" int)
        (field "previous_station" string)
        (field "next_station" string)
        (field "percentageSegment" float)
        (field "delay" int)

