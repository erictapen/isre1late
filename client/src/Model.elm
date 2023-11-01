-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Model exposing
    ( DelayEventsMatrix
    , DelayPerSecond
    , Direction(..)
    , DistanceMatrix
    , Mode(..)
    , ModeTransition
    , Model
    , TouchState
    , TutorialState(..)
    , buildDelayEventsMatrices
    , buildUrl
    , historicSeconds
    , initDistanceMatrix
    , nextMode
    , previousMode
    , stationNames
    , stationPos
    , stations
    , trainPos
    , urlParser
    )

import Browser.Navigation
import Dict exposing (Dict)
import Http
import List exposing (filterMap, foldr, indexedMap)
import Time exposing (Posix)
import Types exposing (DelayEvent, DelayRecord, StationId, Stopover, TripId)
import Url
import Url.Builder as UB
import Url.Parser as UP exposing ((</>))
import Utils exposing (posixToSec)
import Week.Constants


type alias Model =
    { navigationKey : Browser.Navigation.Key
    , mode : Mode
    , modeTransition : ModeTransition
    , tutorialState : TutorialState
    , tutorialProgress : Float
    , delayRecords : Dict TripId (List DelayRecord)
    , delayEvents : Maybe ( DelayEventsMatrix, DelayEventsMatrix )
    , selectedTrip : Result Http.Error (List Stopover)
    , errors : List String
    , now : Maybe Posix
    , timeZone : Maybe Time.Zone
    , direction : Direction
    , distanceMatrix : DistanceMatrix
    , debugText : String
    }


type Mode
    = Trip TripId
    | Hour
    | Day
    | Week


{-| Trip isn't reachable through this
-}
previousMode : Mode -> Maybe Mode
previousMode mode =
    case mode of
        Trip _ ->
            Nothing

        Hour ->
            Nothing

        Day ->
            Just Hour

        Week ->
            Just Day


nextMode : Mode -> Maybe Mode
nextMode mode =
    case mode of
        Trip _ ->
            Nothing

        Hour ->
            Just Day

        Day ->
            Just Week

        Week ->
            Nothing


{-| The information we have to keep about an ongoing transition
progress encodes how far the transition has gone. 0 means stable, -1.0 is a finished transition to the previous mode, 1.0 is a finished transition to the next mode.
-}
type alias ModeTransition =
    { touchState : Maybe TouchState
    , progress : Float
    }


type TutorialState
    = Geographic
    | Location
    | Time
    | Delay
    | Finished


{-| The amount of historic seconds going back from now into the past that are currently displayed.
This depends on the current mode and the progress of the current transition
-}
historicSeconds : Model -> Int
historicSeconds model =
    let
        modeSecs mode =
            case mode of
                Hour ->
                    3600

                Day ->
                    3600 * 24

                Week ->
                    3600 * 24 * 7

                _ ->
                    0

        progress =
            model.modeTransition.progress

        absProgress =
            abs progress

        transitionToSec =
            if progress > 0 then
                Maybe.withDefault 0 <| Maybe.map modeSecs <| nextMode model.mode

            else if progress < 0 then
                Maybe.withDefault 0 <| Maybe.map modeSecs <| previousMode model.mode

            else
                0
    in
    -- TODO: Implement some non-linear transition here?
    round <| ((1 - absProgress) * modeSecs model.mode) + (absProgress * transitionToSec)


type alias TouchState =
    { id : Int
    , progressBeforeTouch : Float
    , startingPos : Float
    , currentPos : Float
    }


buildUrl : Mode -> String
buildUrl mode =
    case mode of
        Trip tid ->
            UB.absolute [ "trip", tid ] []

        Hour ->
            UB.absolute [ "hour" ] []

        Day ->
            UB.absolute [ "day" ] []

        Week ->
            UB.absolute [ "week" ] []


urlParser : UP.Parser (Mode -> a) a
urlParser =
    UP.oneOf
        [ UP.map Trip
            (UP.s "trip"
                </> UP.map (Maybe.withDefault "" << Url.percentDecode) UP.string
            )
        , UP.map Hour (UP.s "hour")
        , UP.map Day (UP.s "day")
        , UP.map Week (UP.s "week")
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


{-| Get the y position of a station, e.g. for legends.
-}
stationPos : DistanceMatrix -> StationId -> Float
stationPos distanceMatrix sid =
    let
        magdeburgHbf =
            900550094
    in
    -- Magdeburg Hbf is the last one in the track, but distanceMatrix wouldn't
    -- contain a value for it, so we just hardcode it to 1
    if sid == magdeburgHbf then
        1

    else
        Maybe.withDefault -1 <|
            Maybe.map (\r -> r.start) <|
                Dict.get ( sid, magdeburgHbf ) distanceMatrix


stations : List ( StationId, StationInfo )
stations =
    [ ( 900470000
      , { name = "Cottbus, Hauptbahnhof"
        , shortName = "Cottbus"
        , important = True
        }
      )
    , ( 900445593
      , { name = "Guben, Bahnhof"
        , shortName = "Guben"
        , important = False
        }
      )
    , ( 900311307
      , { name = "Eisenhüttenstadt, Bahnhof"
        , shortName = "Eisenhüttenstadt"
        , important = False
        }
      )
    , ( 900360000
      , { name = "Frankfurt (Oder), Bahnhof"
        , shortName = "Frankfurt (Oder)"
        , important = True
        }
      )
    , ( 900360004
      , { name = "Frankfurt (Oder), Rosengarten Bhf"
        , shortName = "Rosengarten"
        , important = False
        }
      )
    , ( 900310008
      , { name = "Pillgram, Bahnhof"
        , shortName = "Pillgram"
        , important = False
        }
      )
    , ( 900310007
      , { name = "Jacobsdorf (Mark), Bahnhof"
        , shortName = "Jacobsdorf"
        , important = False
        }
      )
    , ( 900310006
      , { name = "Briesen (Mark), Bahnhof"
        , shortName = "Briesen"
        , important = False
        }
      )
    , ( 900310005
      , { name = "Berkenbrück (LOS), Bahnhof"
        , shortName = "Berkenbrück"
        , important = False
        }
      )
    , ( 900310001
      , { name = "Fürstenwalde, Bahnhof"
        , shortName = "Fürstenwalde"
        , important = False
        }
      )
    , ( 900310002
      , { name = "Hangelsberg, Bahnhof"
        , shortName = "Hangelsberg"
        , important = False
        }
      )
    , ( 900310003
      , { name = "Grünheide, Fangschleuse Bhf"
        , shortName = "Fangschleuse"
        , important = False
        }
      )
    , ( 900310004
      , { name = "S Erkner Bhf"
        , shortName = "Erkner "
        , important = False
        }
      )
    , ( 900120003
      , { name = "S Ostkreuz Bhf (Berlin)"
        , shortName = "Ostkreuz"
        , important = False
        }
      )
    , ( 900120005
      , { name = "S Ostbahnhof (Berlin)"
        , shortName = "Ostbahnhof"
        , important = False
        }
      )
    , ( 900100003
      , { name = "S+U Alexanderplatz Bhf (Berlin)"
        , shortName = "Alexanderplatz"
        , important = False
        }
      )
    , ( 900100001
      , { name = "S+U Friedrichstr. Bhf (Berlin)"
        , shortName = "Friedrichstr."
        , important = False
        }
      )
    , ( 900003201
      , { name = "S+U Berlin Hauptbahnhof"
        , shortName = "Berlin Hbf"
        , important = True
        }
      )
    , ( 900023201
      , { name = "S+U Zoologischer Garten Bhf (Berlin)"
        , shortName = "Zoologischer Garten"
        , important = False
        }
      )
    , ( 900024101
      , { name = "S Charlottenburg Bhf (Berlin)"
        , shortName = "Charlottenburg"
        , important = False
        }
      )
    , ( 900053301
      , { name = "S Wannsee Bhf (Berlin)"
        , shortName = "Wannsee"
        , important = False
        }
      )
    , ( 900230999
      , { name = "S Potsdam Hauptbahnhof"
        , shortName = "Potsdam"
        , important = True
        }
      )
    , ( 900230006
      , { name = "Potsdam, Charlottenhof Bhf"
        , shortName = "Charlottenhof"
        , important = False
        }
      )
    , ( 900230007
      , { name = "Potsdam, Park Sanssouci Bhf"
        , shortName = "Park Sanssouci"
        , important = False
        }
      )
    , ( 900220009
      , { name = "Werder (Havel), Bahnhof"
        , shortName = "Werder (Havel)"
        , important = False
        }
      )
    , ( 900220699
      , { name = "Groß Kreutz, Bahnhof"
        , shortName = "Groß Kreutz"
        , important = False
        }
      )
    , ( 900220182
      , { name = "Götz, Bahnhof"
        , shortName = "Götz"
        , important = False
        }
      )
    , ( 900275110
      , { name = "Brandenburg, Hauptbahnhof"
        , shortName = "Brandenburg"
        , important = True
        }
      )
    , ( 900275719
      , { name = "Brandenburg, Kirchmöser Bhf"
        , shortName = "Kirchmöser"
        , important = False
        }
      )
    , ( 900220249
      , { name = "Wusterwitz, Bahnhof"
        , shortName = "Wusterwitz"
        , important = False
        }
      )
    , ( 900550073
      , { name = "Genthin, Bahnhof"
        , shortName = "Genthin"
        , important = False
        }
      )
    , ( 900550078
      , { name = "Güsen, Bahnhof"
        , shortName = "Güsen"
        , important = False
        }
      )
    , ( 900550062
      , { name = "Burg (bei Magdeburg), Bahnhof"
        , shortName = "Burg (bei Magdeburg)"
        , important = False
        }
      )
    , ( 900550255
      , { name = "Magdeburg-Neustadt, Bahnhof"
        , shortName = "Magdeburg-Neustadt"
        , important = False
        }
      )
    , ( 900550094
      , { name = "Magdeburg, Hauptbahnhof"
        , shortName = "Magdeburg"
        , important = True
        }
      )
    ]


type alias StationInfo =
    { name : String
    , shortName : String
    , important : Bool
    }


stationNames =
    Dict.fromList stations


{-| Place a train going inbetween two stations in the y axis of the entire diagram.
Result contains the y axis value (between 0 and 1), the direction the train
must be going in and wether it skips any stations on its path.
-}
trainPos : DistanceMatrix -> StationId -> StationId -> Float -> Maybe ( Float, Direction, Bool )
trainPos distanceMatrix from to percentageSegment =
    case Dict.get ( from, to ) distanceMatrix of
        Just { start, end, direction, skipsStations } ->
            Just
                ( case direction of
                    Eastwards ->
                        start + (end - start) * percentageSegment

                    Westwards ->
                        start - (start - end) * percentageSegment
                , direction
                , skipsStations
                )

        Nothing ->
            Nothing


type alias DelayPerSecond =
    Int


type alias DelayEventsMatrix =
    Dict ( Int, Int ) DelayPerSecond


{-| For now these matrices are intended to be used for the week mode
First one is Eastwards, second one is Westwards
-}
buildDelayEventsMatrices :
    List DelayEvent
    -> Posix
    -> DistanceMatrix
    -> ( DelayEventsMatrix, DelayEventsMatrix )
buildDelayEventsMatrices delayEvents now distanceMatrix =
    let
        nowSec =
            posixToSec now

        -- the row the event is placed in
        -- TODO this needs to be able to produce multiple rows, especially for aggregated DelayEvents
        maybeTrainPos de =
            Maybe.map (\( yPos, direction, _ ) -> ( round <| yPos * Week.Constants.rows, direction ))
                (trainPos distanceMatrix de.previous_station de.next_station de.percentage_segment)

        -- Helper function insert a DelayEvent into a Matrix
        updateMatrix dict row de =
            Dict.update
                ( (nowSec - de.time) // Week.Constants.secondsPerColumn, row )
                (\i -> Just (Maybe.withDefault 0 i + de.delay * de.duration))
                dict

        -- Insert a DelayEvent into either the Westwards or the Eastwards
        -- matrix (or none at all if we can't position it)
        updateMatrices :
            DelayEvent
            -> ( DelayEventsMatrix, DelayEventsMatrix )
            -> ( DelayEventsMatrix, DelayEventsMatrix )
        updateMatrices de ( dictEastwards, dictWestwards ) =
            case maybeTrainPos de of
                Nothing ->
                    ( dictEastwards, dictWestwards )

                Just ( row, Eastwards ) ->
                    ( updateMatrix dictEastwards row de, dictWestwards )

                Just ( row, Westwards ) ->
                    ( dictEastwards, updateMatrix dictWestwards row de )
    in
    foldr updateMatrices ( Dict.empty, Dict.empty ) delayEvents
