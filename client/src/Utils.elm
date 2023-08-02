-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Utils exposing (onTouch, posixSecToSvg, posixToSec, posixToSvgQuotient, touchCoordinates)

import Html as H
import Html.Events.Extra.Touch as Touch
import Time exposing (Posix, posixToMillis)


{-| An utility function copied from here:
<https://package.elm-lang.org/packages/mpizenberg/elm-pointer-events/latest/Html-Events-Extra-Touch#Touch>
-}
touchCoordinates : Touch.Event -> ( Float, Float )
touchCoordinates touchEvent =
    List.head touchEvent.changedTouches
        |> Maybe.map .clientPos
        |> Maybe.withDefault ( 0, 0 )


{-| Helper function to construct a touch handler with Touch.EventOptions
-}
onTouch : String -> (Touch.Event -> msg) -> H.Attribute msg
onTouch on =
    { stopPropagation = False, preventDefault = False }
        |> Touch.onWithOptions on


removeNothings : List (Maybe a) -> List a
removeNothings =
    List.filterMap identity


posixToSec : Posix -> Int
posixToSec p =
    posixToMillis p // 1000


{-| Some point in the past as Posix time. Apparently, SVG viewBox can't handle full posix numbers.
-}
somePointInThePast : Int
somePointInThePast =
    1688162400


posixToSvgQuotient =
    100000


{-| Turn a Posix sec into a position on the SVG canvas.
SVG viewBox can't handle even a full year in seconds, so we move the comma.
Also we normalise by some point in the past.
-}
posixSecToSvg : Int -> Float
posixSecToSvg secs =
    toFloat (secs - somePointInThePast) / posixToSvgQuotient
