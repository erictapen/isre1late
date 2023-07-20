module Msg exposing (Msg(..))

import Time exposing (Posix)
import Browser exposing (UrlRequest(..))
import Time


type Msg
    = UrlChange UrlRequest
    | Send
    | RecvWebsocket String
    | CurrentTime Posix
    | CurrentTimeZone Time.Zone
    | ToggleDirection

