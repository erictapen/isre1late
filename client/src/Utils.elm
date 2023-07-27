-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Utils exposing (onTouch, touchCoordinates)

import Html as H
import Html.Events.Extra.Touch as Touch


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
