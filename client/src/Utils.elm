-- SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


module Utils exposing
    ( httpErrorToString
    , maybe
    , onTouch
    , percentageStr
    , posixSecToSvg
    , posixToSec
    , posixToSvgQuotient
    , removeNothings
    , touchCoordinates
    )

import Html as H
import Html.Events.Extra.Touch as Touch
import Http exposing (Error(..))
import String exposing (fromFloat)
import Time exposing (Posix, posixToMillis)


{-| Encode values between 0.0 and 1.0
-}
percentageStr : Float -> String
percentageStr p =
    fromFloat (p * 100) ++ "%"


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


maybe : Bool -> a -> Maybe a
maybe b value =
    case b of
        True ->
            Just value

        False ->
            Nothing


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


{-| From here:
<https://stackoverflow.com/questions/56442885/error-when-convert-http-error-to-string-with-tostring-in-elm-0-19>
-}
httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        BadUrl url ->
            "The URL " ++ url ++ " was invalid"

        Timeout ->
            "Unable to reach the server, try again"

        NetworkError ->
            "Unable to reach the server, check your network connection"

        BadStatus 500 ->
            "The server had a problem, try again later"

        BadStatus 400 ->
            "Verify your information and try again"

        BadStatus _ ->
            "Unknown error"

        BadBody errorMessage ->
            errorMessage
