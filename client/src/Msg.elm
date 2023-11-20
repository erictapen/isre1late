-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Msg exposing (Msg(..), TouchMsgType(..))

import Browser exposing (UrlRequest(..))
import Http
import Model exposing (Mode, TutorialState)
import Time exposing (Posix)
import Types exposing (DelayEvent, Stopover, TripId)


type Msg
    = UrlChange UrlRequest
    | Send
    | RecvWebsocket String
    | CurrentTime Posix
    | AnimationFrame Float
    | CurrentTimeZone Time.Zone
    | ViewportHeight Float
    | ToggleDirection
    | TouchMsgTitle Int TouchMsgType ( Float, Float )
    | TouchMsgBottomSheet TouchMsgType ( Float, Float )
    | ModeSwitch Mode Float
    | GotDelayEvents Posix (Result Http.Error (List DelayEvent))
    | OpenTrip TripId
    | GotTrip (Result Http.Error (List Stopover))
    | SetTutorialState TutorialState
    | TimerTick Float
    | SetInfoState Bool


type TouchMsgType
    = Start
    | Move
    | End
    | Cancel
