-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Msg exposing (Msg(..))

import Browser exposing (UrlRequest(..))
import Time exposing (Posix)


type Msg
    = UrlChange UrlRequest
    | Send
    | RecvWebsocket String
    | CurrentTime Posix
    | CurrentTimeZone Time.Zone
    | ToggleDirection
