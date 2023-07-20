-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Utils exposing (touchCoordinates)

import Html.Events.Extra.Touch as Touch


{-| An utility function copied from here:
<https://package.elm-lang.org/packages/mpizenberg/elm-pointer-events/latest/Html-Events-Extra-Touch#Touch>
-}
touchCoordinates : Touch.Event -> ( Float, Float )
touchCoordinates touchEvent =
    List.head touchEvent.changedTouches
        |> Maybe.map .clientPos
        |> Maybe.withDefault ( 0, 0 )


removeNothings : List (Maybe a) -> List a
removeNothings =
    List.filterMap identity
