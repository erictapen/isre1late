-- SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
-- SPDX-License-Identifier: GPL-3.0-or-later


port module Main exposing (main)

import Browser exposing (Document)
import Dict exposing (Dict)
import Json.Decode as JD exposing (decodeString)
import Time exposing (Posix)
import Types exposing (Delay, TripId, decodeClientMsg)


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


type Msg
    = Send
    | RecvWebsocket String


subscriptions : Model -> Sub Msg
subscriptions _ =
    messageReceiver RecvWebsocket


type alias Model =
    { delays : Dict TripId (List Delay)
    , errors : List String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { delays = Dict.empty, errors = [] }, Cmd.none )


view : Model -> Document Msg
view model =
    { title = "Is RE1 late?"
    , body = []
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RecvWebsocket jsonStr ->
            case decodeString decodeClientMsg jsonStr of
                Ok ( tripId, delay ) ->
                    ( { model
                        | delays =
                            Dict.update tripId
                                (\maybeList ->
                                    Just <|
                                        delay
                                            :: Maybe.withDefault [] maybeList
                                )
                                model.delays
                      }
                    , Cmd.none
                    )

                Err e ->
                    ( { model | errors = JD.errorToString e :: model.errors }, Cmd.none )

        Send ->
            ( model, sendMessage "" )


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
