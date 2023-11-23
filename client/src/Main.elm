-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (main)

import Browser exposing (UrlRequest(..))
import Browser.Events exposing (onAnimationFrameDelta)
import Browser.Navigation
import Components.BottomSheet
import Components.Diagram
import Components.InfoButton
import Components.Menu
import Components.StationLegend
import Components.TimeLegend
import Components.Title
import Dict exposing (Dict)
import Html as H exposing (Html, button, div, h1, p, text)
import Html.Attributes as HA exposing (class, id, style)
import Html.Events exposing (onClick)
import Html.Events.Extra.Touch as Touch
import Http
import Json.Decode as JD exposing (decodeString)
import List exposing (filterMap, head, indexedMap, map)
import Model
    exposing
        ( Direction(..)
        , DistanceMatrix
        , Mode(..)
        , ModeTransition
        , Model
        , TutorialState(..)
        , buildDelayEventsMatrices
        , buildUrl
        , historicSeconds
        , initDistanceMatrix
        , nextMode
        , previousMode
        , stationNames
        , stations
        , trainPos
        , urlParser
        )
import Msg exposing (Msg(..), TouchMsgType(..))
import String exposing (fromFloat, fromInt)
import Svg as S exposing (Svg, g, line, path, svg, text_)
import Svg.Attributes as SA
    exposing
        ( d
        , fill
        , fontSize
        , height
        , preserveAspectRatio
        , stroke
        , strokeWidth
        , viewBox
        , width
        , x
        , x1
        , x2
        , y
        , y1
        , y2
        )
import Svg.Loaders
import Task
import Time exposing (Posix, millisToPosix, posixToMillis)
import Trip.View
import Tutorial
import Types
    exposing
        ( DelayRecord
        , StationId
        , TripId
        , decodeDelayEvents
        , decodeDelayRecord
        , decodeTrip
        )
import Url
import Url.Builder
import Url.Parser as UP
import Utils
    exposing
        ( getViewportHeight
        , httpErrorToString
        , onTouch
        , posixSecToSvg
        , posixToSec
        , posixToSvgQuotient
        , touchCoordinates
        )


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port rebuildSocket : String -> Cmd msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ messageReceiver RecvWebsocket

        -- TODO synchronise this with RecvWebsocket after the loading state is implemented
        , Time.every 1000 CurrentTime
        , case ( model.modeTransition.progress /= 0, model.modeTransition.touchState ) of
            ( True, Nothing ) ->
                onAnimationFrameDelta AnimationFrame

            _ ->
                Sub.none
        , Tutorial.subscriptions model.tutorialState
        ]


wsApiUrl =
    Url.Builder.crossOrigin
        "wss://isre1late.erictapen.name"
        [ "api", "ws", "delays" ]
        [ Url.Builder.int "historic" <| 3600 * 24 ]


httpApiBaseUrl =
    "api"


init : () -> Url.Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        defaultMode =
            Hour

        modeFromUrl =
            UP.parse urlParser url

        initModel =
            { navigationKey = key
            , mode = Maybe.withDefault defaultMode modeFromUrl
            , modeTransition = { touchState = Nothing, progress = 0 }
            , viewportHeight = 0
            , infoState = { visible = False, dragPos = 0 }
            , tutorialState = Geographic
            , tutorialProgress = 0
            , delayRecords = Dict.empty
            , delayEvents = Nothing
            , selectedTrip = Ok []
            , errors = []
            , now = Nothing
            , timeZone = Nothing
            , direction = Eastwards
            , distanceMatrix = initDistanceMatrix
            , debugText = ""
            }
    in
    ( initModel
    , Cmd.batch
        [ rebuildSocket <| wsApiUrl
        , Task.perform CurrentTimeZone Time.here
        , Task.perform CurrentTime Time.now
        , Task.perform ViewportHeight getViewportHeight
        , case modeFromUrl of
            Just (Trip tripId) ->
                fetchTrip tripId

            Just _ ->
                Cmd.none

            Nothing ->
                Browser.Navigation.pushUrl key <| buildUrl defaultMode
        ]
    )


fetchDelayEvents : Posix -> Cmd Msg
fetchDelayEvents now =
    Http.get
        { url = Url.Builder.absolute [ httpApiBaseUrl, "delay_events", "week" ] []
        , expect = Http.expectJson (GotDelayEvents now) decodeDelayEvents
        }


fetchTrip : String -> Cmd Msg
fetchTrip tripId =
    Http.get
        { url = Url.Builder.absolute [ httpApiBaseUrl, "trip", tripId ] []
        , expect = Http.expectJson GotTrip decodeTrip
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChange urlRequest ->
            case urlRequest of
                External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

                Internal url ->
                    case UP.parse urlParser url of
                        Just newMode ->
                            ( { model | mode = newMode }
                            , Cmd.none
                            )

                        Nothing ->
                            -- TODO Show a 404 site?
                            ( model, Cmd.none )

        RecvWebsocket jsonStr ->
            case decodeString decodeDelayRecord jsonStr of
                Ok ( tripId, delay ) ->
                    ( { model
                        | delayRecords =
                            Dict.update tripId
                                (\maybeList ->
                                    Just <|
                                        delay
                                            :: Maybe.withDefault [] maybeList
                                )
                                model.delayRecords
                      }
                    , Cmd.none
                    )

                Err e ->
                    ( { model | errors = JD.errorToString e :: model.errors }, Cmd.none )

        Send ->
            ( model, sendMessage "" )

        CurrentTime now ->
            ( { model | now = Just now }
              -- If now wasn't set yet, we fetch the delay events once.
            , case model.now of
                Nothing ->
                    fetchDelayEvents now

                _ ->
                    Cmd.none
            )

        CurrentTimeZone zone ->
            ( { model | timeZone = Just zone }, Cmd.none )

        ToggleDirection ->
            ( { model
                | direction =
                    case model.direction of
                        Westwards ->
                            Eastwards

                        Eastwards ->
                            Westwards
              }
            , Cmd.none
            )

        TouchMsgTitle touchId touchType ( _, y ) ->
            let
                oldModeTransition =
                    model.modeTransition

                -- The length in pixels that we would require as a touch event for a full transition.
                -- This doesn't need to be exact, as it just defines how much the finger needs
                -- to travel.
                -- Note that the threshold would kick in way sooner.
                assumedScreenHeight =
                    800

                -- The absolute progress value above which we trigger a transition.
                threshold =
                    0.3

                progressDelta touchState =
                    (touchState.startingPos - y) / assumedScreenHeight

                newProgress touchState =
                    touchState.progressBeforeTouch + progressDelta touchState
            in
            case ( touchType, model.modeTransition.touchState ) of
                ( Start, Nothing ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState =
                                    Just
                                        { id = touchId
                                        , startingPos = y
                                        , currentPos = y
                                        , progressBeforeTouch = oldModeTransition.progress
                                        }
                            }
                      }
                    , Cmd.none
                    )

                ( Move, Just touchState ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Just { touchState | currentPos = y }
                                , progress = newProgress touchState
                            }
                      }
                    , Cmd.none
                    )

                -- The gesture finished and we evaluate wether a transition is going to happen.
                ( End, Just touchState ) ->
                    let
                        nP =
                            newProgress touchState

                        ( transitionTriggered, newMode ) =
                            if abs nP > threshold then
                                case
                                    if nP > 0 then
                                        nextMode model.mode

                                    else
                                        previousMode model.mode
                                of
                                    Just nM ->
                                        ( True, nM )

                                    -- TODO figure out wether we want to move
                                    -- the element at all in this case. Could
                                    -- be that the moving h1 is confusing to
                                    -- the user, when no further transition is
                                    -- possible anyway.
                                    Nothing ->
                                        ( False, model.mode )

                            else
                                ( False, model.mode )
                    in
                    ( { model
                        | mode = newMode
                        , modeTransition =
                            { oldModeTransition
                                | touchState = Nothing
                                , progress =
                                    if transitionTriggered then
                                        if nP > 0 then
                                            nP - 1

                                        else
                                            nP + 1

                                    else
                                        nP
                            }
                      }
                    , if transitionTriggered then
                        Browser.Navigation.pushUrl model.navigationKey <| buildUrl newMode

                      else
                        Cmd.none
                    )

                ( Cancel, Just touchState ) ->
                    ( { model
                        | modeTransition =
                            { oldModeTransition
                                | touchState = Nothing
                            }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ModeSwitch newMode progress ->
            ( { model
                | mode = newMode

                -- TODO set progress appropriately
                , modeTransition = { touchState = Nothing, progress = progress }
              }
            , if model.mode /= newMode then
                Browser.Navigation.pushUrl model.navigationKey <| buildUrl newMode

              else
                Cmd.none
            )

        AnimationFrame delta ->
            let
                oldModeTransition =
                    model.modeTransition

                oldProgress =
                    oldModeTransition.progress

                -- Time in ms it would take for a full progress to "cool down" to 0
                transitionDuration =
                    1000

                progressDelta =
                    delta / transitionDuration
            in
            ( { model
                | modeTransition =
                    { oldModeTransition
                        | progress =
                            if oldProgress > 0 then
                                max 0 (oldProgress - progressDelta)

                            else
                                min 0 (oldProgress + progressDelta)
                    }
              }
            , Cmd.none
            )

        TouchMsgBottomSheet touchType ( _, y ) ->
            let
                oldInfoState =
                    model.infoState

                defaultHeight =
                    0.5 * model.viewportHeight

                minimumHeight =
                    0.3 * model.viewportHeight
            in
            case touchType of
                Start ->
                    ( model, Cmd.none )

                Move ->
                    ( { model | infoState = { oldInfoState | dragPos = y } }, Cmd.none )

                End ->
                    ( { model
                        | infoState =
                            if model.viewportHeight - oldInfoState.dragPos < minimumHeight then
                                { visible = False, dragPos = defaultHeight }

                            else
                                { visible = True, dragPos = defaultHeight }
                      }
                    , Cmd.none
                    )

                Cancel ->
                    ( { model
                        | infoState =
                            { oldInfoState
                                | dragPos = defaultHeight
                            }
                      }
                    , Cmd.none
                    )

        GotDelayEvents now httpResult ->
            ( case httpResult of
                Ok delayEvents ->
                    { model
                        | delayEvents =
                            Just <|
                                buildDelayEventsMatrices delayEvents now model.distanceMatrix
                        , debugText = "DelayEvents received"
                    }

                Err e ->
                    { model | delayEvents = Nothing, debugText = httpErrorToString e }
            , Cmd.none
            )

        OpenTrip tripId ->
            let
                newMode =
                    Trip tripId
            in
            ( { model | mode = newMode, selectedTrip = Ok [] }
            , Cmd.batch
                [ Browser.Navigation.pushUrl model.navigationKey <| buildUrl newMode
                , fetchTrip tripId
                ]
            )

        GotTrip stopoverResult ->
            ( { model | selectedTrip = stopoverResult }, Cmd.none )

        SetTutorialState tutorialState ->
            ( { model | tutorialState = tutorialState, tutorialProgress = 0 }
            , Cmd.none
            )

        TimerTick delta ->
            let
                newProgress =
                    model.tutorialProgress + delta
            in
            if newProgress > Tutorial.animationDuration model.tutorialState then
                ( { model
                    | tutorialProgress = 0
                    , tutorialState = Tutorial.next model.tutorialState
                  }
                , Cmd.none
                )

            else
                ( { model | tutorialProgress = newProgress }
                , Cmd.none
                )

        SetInfoState v ->
            ( { model | infoState = { dragPos = model.viewportHeight * 0.5, visible = v } }
            , Task.perform ViewportHeight getViewportHeight
            )

        ViewportHeight height ->
            ( { model | viewportHeight = height }, Cmd.none )


view : Model -> Browser.Document Msg
view model =
    { title = "How late is RE1?"
    , body =
        case ( model.timeZone, model.now ) of
            ( Just timeZone, Just now ) ->
                let
                    hisSeconds =
                        historicSeconds model
                in
                [ div
                    [ id "app"
                    ]
                    (case ( model.tutorialState, model.mode ) of
                        ( Finished, Trip tripId ) ->
                            Trip.View.view tripId model.selectedTrip

                        ( Finished, _ ) ->
                            [ Components.Title.view model.mode model.modeTransition.progress
                            , Components.InfoButton.view model.infoState
                            , div [ id "row1" ]
                                [ Components.Diagram.view model now hisSeconds timeZone
                                , Components.StationLegend.view model.distanceMatrix model.direction
                                ]
                            , div [ id "row2" ]
                                [ if model.modeTransition.progress == 0 then
                                    Components.TimeLegend.view model.mode hisSeconds timeZone now

                                  else
                                    div [] []
                                , div [ class "station-legend" ] []
                                ]
                            , div [ id "row3" ] <| Components.Menu.view model.mode
                            , Components.BottomSheet.view
                                model.infoState
                                model.mode
                                model.viewportHeight
                            ]

                        ( tutorialState, _ ) ->
                            Tutorial.view tutorialState model.distanceMatrix
                    )
                ]

            _ ->
                [ div [ id "loading-screen" ]
                    [ Svg.Loaders.grid
                        [ Svg.Loaders.size 300, Svg.Loaders.color "#dddddd" ]
                    ]
                ]
    }


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlChange
        , onUrlChange = UrlChange << Browser.Internal
        }
