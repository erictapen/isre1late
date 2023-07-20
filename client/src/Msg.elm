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
