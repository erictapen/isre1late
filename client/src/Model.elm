module Model exposing (Model, Mode(..), buildUrl, urlParser, Direction(..), stations, DistanceMatrix, initDistanceMatrix, stationNames)

import Browser.Navigation
import Time exposing (Posix)
import Dict exposing (Dict)
import Types exposing (StationId, TripId, DelayRecord)
import List exposing (indexedMap, filterMap)
import Url.Parser as UP


type alias Model =
    { navigationKey : Browser.Navigation.Key
    , mode : Mode
    , delayRecords : Dict TripId (List DelayRecord)
    , errors : List String
    , now : Maybe Posix
    , timeZone : Maybe Time.Zone
    , historicSeconds : Int
    , direction : Direction
    , distanceMatrix : DistanceMatrix
    }

type Mode
    = SingleTrip
    | Hour
    | Day
    | Week
    | Year


buildUrl : Mode -> String
buildUrl mode =
    "/"
        ++ (case mode of
                SingleTrip ->
                    "trip"

                Hour ->
                    "hour"

                Day ->
                    "day"

                Week ->
                    "week"

                Year ->
                    "year"
           )

urlParser : UP.Parser (Mode -> a) a
urlParser =
    UP.oneOf
        [ UP.map SingleTrip (UP.s "trip")
        , UP.map Hour (UP.s "hour")
        , UP.map Day (UP.s "day")
        , UP.map Week (UP.s "week")
        , UP.map Year (UP.s "year")
        ]





type Direction
    = Westwards
    | Eastwards


type alias DistanceMatrix =
    Dict
        ( StationId, StationId )
        { start : Float
        , end : Float
        , direction : Direction
        , skipsStations : Bool
        }


{-| A matrix that contains the positions for every combination of stations,
along with the direction the two stations are facing and wether they would
skip any stations on the RE1 track.

This scales quadratically, so be careful with the number of stations!

-}
initDistanceMatrix : DistanceMatrix
initDistanceMatrix =
    let
        -- We subtract one, because we place by zero-led index
        stationsCount =
            toFloat <| List.length stations - 1

        stationId =
            Tuple.first

        oneToNDistances direction cursorIndex ( cursorSid, _ ) =
            indexedMap
                (\i ( sid, _ ) ->
                    if cursorIndex >= i then
                        Nothing

                    else
                        Just
                            ( ( cursorSid, sid )
                            , { start = toFloat cursorIndex / stationsCount
                              , end = toFloat i / stationsCount
                              , direction = direction
                              , skipsStations =
                                    if i > cursorIndex + 1 then
                                        True

                                    else
                                        False
                              }
                            )
                )
            <|
                case direction of
                    Westwards ->
                        stations

                    Eastwards ->
                        List.reverse stations
    in
    Dict.fromList <|
        filterMap identity <|
            List.concat <|
                indexedMap (oneToNDistances Westwards) stations
                    ++ (indexedMap (oneToNDistances Eastwards) <| List.reverse stations)

stations : List ( StationId, StationInfo )
stations =
    [ ( 900470000
      , { name = "Cottbus, Hauptbahnhof"
        , shortName = "Cottbus"
        }
      )
    , ( 900445593
      , { name = "Guben, Bahnhof"
        , shortName = "Guben"
        }
      )
    , ( 900311307
      , { name = "Eisenhüttenstadt, Bahnhof"
        , shortName = "Eisenhüttenstadt"
        }
      )
    , ( 900360000
      , { name = "Frankfurt (Oder), Bahnhof"
        , shortName = "Frankfurt (Oder)"
        }
      )
    , ( 900360004
      , { name = "Frankfurt (Oder), Rosengarten Bhf"
        , shortName = "Rosengarten"
        }
      )
    , ( 900310008
      , { name = "Pillgram, Bahnhof"
        , shortName = "Pillgram"
        }
      )
    , ( 900310007
      , { name = "Jacobsdorf (Mark), Bahnhof"
        , shortName = "Jacobsdorf"
        }
      )
    , ( 900310006
      , { name = "Briesen (Mark), Bahnhof"
        , shortName = "Briesen"
        }
      )
    , ( 900310005
      , { name = "Berkenbrück (LOS), Bahnhof"
        , shortName = "Berkenbrück"
        }
      )
    , ( 900310001
      , { name = "Fürstenwalde, Bahnhof"
        , shortName = "Fürstenwalde"
        }
      )
    , ( 900310002
      , { name = "Hangelsberg, Bahnhof"
        , shortName = "Hangelsberg"
        }
      )
    , ( 900310003
      , { name = "Grünheide, Fangschleuse Bhf"
        , shortName = "Fangschleuse"
        }
      )
    , ( 900310004
      , { name = "S Erkner Bhf"
        , shortName = "Erkner "
        }
      )
    , ( 900120003
      , { name = "S Ostkreuz Bhf (Berlin)"
        , shortName = "Ostkreuz"
        }
      )
    , ( 900120005
      , { name = "S Ostbahnhof (Berlin)"
        , shortName = "Ostbahnhof"
        }
      )
    , ( 900100003
      , { name = "S+U Alexanderplatz Bhf (Berlin)"
        , shortName = "Alexanderplatz"
        }
      )
    , ( 900100001
      , { name = "S+U Friedrichstr. Bhf (Berlin)"
        , shortName = "Friedrichstr."
        }
      )
    , ( 900003201
      , { name = "S+U Berlin Hauptbahnhof"
        , shortName = "Berlin Hbf"
        }
      )
    , ( 900023201
      , { name = "S+U Zoologischer Garten Bhf (Berlin)"
        , shortName = "Zoologischer Garten"
        }
      )
    , ( 900024101
      , { name = "S Charlottenburg Bhf (Berlin)"
        , shortName = "Charlottenburg"
        }
      )
    , ( 900053301
      , { name = "S Wannsee Bhf (Berlin)"
        , shortName = "Wannsee"
        }
      )
    , ( 900230999
      , { name = "S Potsdam Hauptbahnhof"
        , shortName = "Potsdam"
        }
      )
    , ( 900230006
      , { name = "Potsdam, Charlottenhof Bhf"
        , shortName = "Charlottenhof"
        }
      )
    , ( 900230007
      , { name = "Potsdam, Park Sanssouci Bhf"
        , shortName = "Park Sanssouci"
        }
      )
    , ( 900220009
      , { name = "Werder (Havel), Bahnhof"
        , shortName = "Werder (Havel)"
        }
      )
    , ( 900220699
      , { name = "Groß Kreutz, Bahnhof"
        , shortName = "Groß Kreutz"
        }
      )
    , ( 900220182
      , { name = "Götz, Bahnhof"
        , shortName = "Götz"
        }
      )
    , ( 900275110
      , { name = "Brandenburg, Hauptbahnhof"
        , shortName = "Brandenburg"
        }
      )
    , ( 900275719
      , { name = "Brandenburg, Kirchmöser Bhf"
        , shortName = "Kirchmöser"
        }
      )
    , ( 900220249
      , { name = "Wusterwitz, Bahnhof"
        , shortName = "Wusterwitz"
        }
      )
    , ( 900550073
      , { name = "Genthin, Bahnhof"
        , shortName = "Genthin"
        }
      )
    , ( 900550078
      , { name = "Güsen, Bahnhof"
        , shortName = "Güsen"
        }
      )
    , ( 900550062
      , { name = "Burg (bei Magdeburg), Bahnhof"
        , shortName = "Burg (bei Magdeburg)"
        }
      )
    , ( 900550255
      , { name = "Magdeburg-Neustadt, Bahnhof"
        , shortName = "Magdeburg-Neustadt"
        }
      )
    , ( 900550094
      , { name = "Magdeburg, Hauptbahnhof"
        , shortName = "Magdeburg"
        }
      )
    ]

type alias StationInfo =
    { name : String
    , shortName : String
    }




stationNames =
    Dict.fromList stations


