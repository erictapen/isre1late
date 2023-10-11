-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Msg exposing (Msg(..), TouchMsgType(..))

import Browser exposing (UrlRequest(..))
import Http
import Model exposing (Mode)
import Time exposing (Posix)
import Types exposing (DelayEvent, Stopover, TripId)


type Msg
    = UrlChange UrlRequest
    | Send
    | RecvWebsocket String
    | CurrentTime Posix
    | AnimationFrame Float
    | CurrentTimeZone Time.Zone
    | ToggleDirection
    | TouchMsg Int TouchMsgType ( Float, Float )
    | ModeSwitch Mode Float
    | GotDelayEvents (Result Http.Error (List DelayEvent))
    | OpenTrip TripId
    | GotTrip (Result Http.Error (List Stopover))
    | SkipTutorial


type TouchMsgType
    = Start
    | Move
    | End
    | Cancel
