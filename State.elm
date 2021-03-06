port module State exposing (..)

import String
import Array exposing (Array)
import Dict exposing (Dict)
import Time exposing (Time)
import Json.Decode as JD exposing ((:=), decodeValue)
import Json.Encode as JE exposing (Value)
import Platform.Cmd as Cmd
import Cmd.Extra
import List.Extra
import Json.Encode as JE exposing (Value)
import Debug exposing (log)

import Types exposing (Card, Message, User, Channel, Torrent,
                       Content(..), PeerStatus(..),
                       cardDecoder, encodeCard,
                       userDecoder, encodeUser,
                       messageDecoder, encodeMessage, encodeContent,
                       torrentDecoder, encodeTorrent,
                       Model, CardMode(..), Editing(..))
import Helpers exposing (findIndex)

-- UPDATE

type Msg
    = OpenMenu String
    | TypeMessage String
    | SearchedCard (List Card)
    | PostMessage | SelectMessage String Bool | UnselectMessages
    | PostTorrent Torrent | DownloadTorrent String Torrent | UpdateTorrent String Torrent
    | ClickCard String | UpdateCardContents Action | DeleteCard
    | StartEditing Editing | StopEditing String
    | GotMessage Message
    | AddToCard String (List Message) | AddToNewCard (List Message)
    | GotCard Card | CardDeleted String | FocusCard Card
    | GotUser User | SelectUser User | SetUser String String
    | SelectChannel String | SetChannel String String
    | ConnectWebSocket | WebSocketState Bool | WebRTCState (String, Int) | ReplicationState (String, String)
    | Tick Time
    | NoOp String

type Action = Add | Edit Int Content | Delete Int

port pouchCreate : Value -> Cmd msg
port deleteCard : String -> Cmd msg
port setUserPicture : (String, String) -> Cmd msg
port setChannel : Channel -> Cmd msg
port loadCard : String -> Cmd msg
port searchCard : String -> Cmd msg
port updateCardContents : (String, Int, Value) -> Cmd msg
port wsConnect : Bool -> Cmd msg
port downloadTorrent : (String, Value) -> Cmd msg
port moveToChannel : String -> Cmd msg
port userSelected : String -> Cmd msg
port focusField : String -> Cmd msg
port scrollChat : Int -> Cmd msg
port deselectText : Int -> Cmd msg

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        OpenMenu menu -> { model | menu = menu } ! []
        TypeMessage v ->
            let
                search = 
                    case model.cardMode of
                        Focused _ _ _ -> Cmd.none
                        _ -> searchCard v
                vlen = String.length v
            in
                if model.typing == "" && vlen > 1 then
                    if vlen == (String.length model.prevTyping) + 1 then
                        { model | prevTyping = model.typing } ! []
                    else
                        { model | typing = v, prevTyping = model.typing } ! [ search ]
                else
                    { model | typing = v, prevTyping = model.typing } ! [ search ]
        SearchedCard cards ->
            if List.length cards == 0 then
                { model | cardMode = Normal } ! []
            else
                { model | cardMode = SearchResults cards } ! []
        PostMessage ->
            let
                text = model.typing |> String.trim
                newcard =
                    if String.left 6 text == "/card " then
                        pouchCreate <|
                            encodeCard (String.dropLeft 5 text) Array.empty
                    else Cmd.none
                deletecard = 
                    if String.left 9 text == "/delete #" then
                        let
                            typed = String.right 5 text
                            match = List.Extra.find (.id >> String.right 5 >> (==) typed)
                        in
                            case match model.cards of
                                Just card -> deleteCard card.id
                                Nothing -> Cmd.none
                    else
                        Cmd.none
                newmessage = pouchCreate <| encodeMessage model.me text Nothing
            in
                { model
                    | typing = ""
                    , prevTyping = model.typing
                    , cardMode =
                        case model.cardMode of
                            SearchResults _ -> Normal
                            _ -> model.cardMode
                } ! [ newmessage, newcard, deletecard, scrollChat 90 ]
        SelectMessage id shiftPressed ->
            if shiftPressed then
                let
                    mapcomplex : List String -> Message -> Message
                    mapcomplex acc m =
                        if List.any ((==) m.id) acc then { m | selected = True }
                        else { m | selected = False }
                    accumulator m acc =
                        if (List.any ((==) id) acc) then acc -- past the point of clicked
                        else if List.isEmpty acc then
                            if m.selected then m.id :: acc -- where the selection starts
                            else acc -- the selection hasn't started yet
                        else m.id :: acc -- the selection just keeps going

                    firstselectedindex = findIndex .selected model.messages
                    clickedindex = findIndex (.id >> (==) id) model.messages
                    (reduce, messages) =
                        if firstselectedindex > List.length model.messages then
                            case model.messages of
                                [] -> (List.foldl, model.messages)
                                x::xs ->
                                    (List.foldl, { x | selected = True } :: xs)
                        else if firstselectedindex >= clickedindex then
                            (List.foldr, model.messages)
                        else
                            (List.foldl, model.messages)
                    acc = reduce accumulator [] messages
                in
                    { model | messages = List.map (mapcomplex acc) model.messages }
                    ! [ deselectText 30 ]
            else
                { model | messages = List.map
                    (\m -> if m.id == id then { m | selected = not m.selected } else m)
                    model.messages
                } ! []
        UnselectMessages ->
            { model | messages =
                List.map (\m -> { m | selected = False }) model.messages
            } ! []
        PostTorrent torrent ->
            ( model
            , Cmd.batch
                [ pouchCreate <| encodeMessage model.me "" (Just torrent)
                , scrollChat 90
                ]
            )
        DownloadTorrent messageId torrent ->
            model ! [ downloadTorrent (messageId, encodeTorrent torrent) ]
        UpdateTorrent messageId torrent ->
            { model | messages =
                let
                    mapper : Message -> Message
                    mapper m =
                        if m.id == messageId then
                            case m.torrent of
                                Nothing -> m
                                Just torrent ->
                                    { m | torrent = Just torrent }
                        else m
                in List.map mapper model.messages
            } ! []
        ClickCard id ->
            if id == "" then
                { model | cardMode =
                    case model.cardMode of
                        Focused _ previous _ -> previous
                        _ -> Normal
                } ! []
            else
                model ! [ loadCard id ]
        StartEditing editingState ->
            case model.cardMode of
                Focused card prev _ ->
                    { model | cardMode = Focused card prev editingState } !
                    [ focusField <| "#" ++ card.id ++ " .name input" ]
                _ -> model ! []
        StopEditing val ->
            case model.cardMode of
                Focused card prev editingState ->
                    { model | cardMode =
                        Focused card prev None
                    } !
                    [ updateCardContents
                        (card.id, -1, JE.string <| String.trim val)
                    ]
                _ -> model ! []
        UpdateCardContents action ->
            case model.cardMode of
                Focused card prev _ ->
                    case action of
                        Edit index content ->
                            model !
                            [ updateCardContents
                                (card.id, index, encodeContent content)
                            ]
                        Add ->
                            { model | cardMode = Focused
                                { card | contents = Array.push (Note "") card.contents }
                                prev
                                None
                            } ! []
                        Delete index ->
                            model !
                            [ updateCardContents (card.id, index, JE.null) ]
                _ -> model ! []
        DeleteCard ->
            case model.cardMode of
                Focused card prev _ ->
                    { model
                        | cardMode = prev
                    } !
                    [ pouchCreate <| encodeMessage
                        model.me
                        ("/delete #" ++ (String.right 5 card.id))
                        Nothing
                    , deleteCard card.id
                    ]
                _ -> model ! []
        FocusCard card ->
            { model | cardMode = Focused card model.cardMode None } ! []
        GotMessage message ->
            { model | messages = message :: model.messages } ! [ scrollChat 10 ]
        GotCard card ->
            { model
                | cards =
                    if List.any (.id >> (==) card.id) model.cards then
                        List.map (\c -> if c.id == card.id then card else c) model.cards
                    else
                        card :: model.cards
                , cardMode =
                    case model.cardMode of
                        Focused _ prev  _ -> Focused card prev None
                        _ -> model.cardMode
            } ! []
        CardDeleted cardId ->
            { model
                | cards = List.filter (.id >> (/=) cardId) model.cards
                , cardMode = Normal
            } ! []
        AddToCard id messages ->
            { model | messages = List.map (\m -> { m | selected = False }) model.messages }
            ! [ updateCardContents (id, 999, encodeContent <| Conversation messages) ]
        AddToNewCard messages ->
            { model | messages = List.map (\m -> { m | selected = False }) model.messages }
            ! [
                pouchCreate <|
                    encodeCard "" (Array.fromList [ Conversation messages ])
            ]
        GotUser user ->
            { model
                | users =
                    if List.any (.name >> (==) user.name) model.users then
                        List.map (\c -> if c.name == user.name then user else c) model.users
                    else
                        user :: model.users
                , me =
                    if model.me.machineId == user.machineId then
                        if model.me.machineId == model.me.name then user
                        else if model.me.name == user.name then user
                        else model.me
                    else model.me
            } ! []
        SelectUser user -> { model | me = user } ! [ userSelected user.name ]
        SetUser name pictureURL ->
            model ! [ setUserPicture (name, pictureURL) ]
        SetChannel wsurl couchurl ->
            let
                channel = Channel model.channel.name wsurl couchurl
            in
                { model | channel = channel } ! [ setChannel channel ]
        SelectChannel channelName -> model ! [ moveToChannel channelName ]
        ConnectWebSocket -> model ! [ wsConnect True ]
        WebSocketState wsup ->
            { model
                | websocket = wsup
                , webrtc =
                    if wsup then model.webrtc
                    else Dict.map
                        (\_ ps ->
                            case ps of
                                Connected _ -> ps 
                                _ -> Closed
                        )
                        model.webrtc
            } ! []
        WebRTCState (otherMachineId, connState) ->
            { model
                | webrtc = Dict.insert otherMachineId
                    ( case connState of
                        0 -> Connecting
                        1 -> Connected { replicating = False, lastSent = 0, lastReceived = 0 }
                        3 -> Closed
                        _ -> Weird connState
                    )
                    model.webrtc
            } ! []
        ReplicationState (otherMachineId, action) ->
            { model | webrtc = 
                Dict.update otherMachineId
                    ( \v -> case v of
                        Just (Connected data) -> Just <| Connected
                            { data
                                | replicating =
                                    case action of
                                        "<replicating>" -> True
                                        "<sent>" -> False
                                        _ -> data.replicating
                                , lastSent = if action == "<sent>" then 0 else data.lastSent
                                , lastReceived = if action == "<received>" then 0 else data.lastReceived
                            }
                        _ -> Nothing
                    )
                    model.webrtc
            } ! []
        Tick _ ->
            { model | webrtc = Dict.map
                (\_ ps -> case ps of
                    Connected data -> Connected
                        { data
                            | lastSent = data.lastSent + tickInterval
                            , lastReceived = data.lastReceived + tickInterval
                        }
                    _ -> ps
                )
                model.webrtc
            } ! []
        NoOp _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

port pouchMessages : (Value -> msg) -> Sub msg
port pouchCards : (Value -> msg) -> Sub msg
port pouchUsers : (Value -> msg) -> Sub msg
port cardDeleted : (String -> msg) -> Sub msg
port cardLoaded : (Value -> msg) -> Sub msg
port currentUser : (Value -> msg) -> Sub msg
port searchedCard : (Value -> msg) -> Sub msg
port droppedFileChat : (Value -> msg) -> Sub msg
port droppedFileCards : (Value -> msg) -> Sub msg
port droppedTextChat : (String -> msg) -> Sub msg
port droppedTextCards : (String -> msg) -> Sub msg
port torrentInfo : ((String, Value) -> msg) -> Sub msg
port websocket : (Bool  -> msg) -> Sub msg
port webrtc : ((String, Int) -> msg) -> Sub msg
port replication : ((String, String) -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    let
        decodeOrFail : JD.Decoder a -> (a -> Msg) -> Value -> Msg
        decodeOrFail decoder tagger value =
            case decodeValue decoder value of
                Ok decoded -> tagger decoded
                Err err -> NoOp <| log ("error decoding " ++ (toString value)) err
    in
        Sub.batch
            [ pouchMessages <| decodeOrFail messageDecoder GotMessage
            , pouchCards <| decodeOrFail cardDecoder GotCard
            , pouchUsers <| decodeOrFail userDecoder GotUser
            , cardDeleted CardDeleted
            , cardLoaded <| decodeOrFail cardDecoder FocusCard
            , currentUser <| decodeOrFail userDecoder SelectUser
            , searchedCard <| decodeOrFail (JD.list cardDecoder) SearchedCard
            , droppedFileChat <| decodeOrFail torrentDecoder PostTorrent
            , torrentInfo <| \(mid, val) -> decodeOrFail torrentDecoder (UpdateTorrent mid) val
            -- , droppedTextChat PostMessage
            -- , droppedTextCards AddTextToCard
            , websocket WebSocketState
            , webrtc WebRTCState
            , replication ReplicationState
            , Time.every tickInterval Tick
            ]


tickInterval = Time.second * 10
