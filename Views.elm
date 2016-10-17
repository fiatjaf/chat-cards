module Views exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Dict exposing (Dict)
import Array
import Json.Decode as JD exposing ((:=), decodeValue)

import State exposing (Model, CardMode(..),
                       Msg(..), Action(..))
import Types exposing (Card, Message, Content(..),
                       cardDecoder, messageDecoder,
                       encodeCard, encodeMessage)

-- VIEW

view : Model -> Html Msg
view model =
    node "main" []
        [ section [ id "chat" ] [ chatView model ]
        , section [ id "cards" ] [ cardsView model ]
        ]

chatView : Model -> Html Msg
chatView model =
    div []
        [ lazy messageActionView model
        , Keyed.node "div" [ id "messages" ]
            ( model.messages
                |> List.take 50
                |> List.reverse
                |> List.map (\m -> (m.id, lazy2 messageView model.userPictures m))
            )
        , node "form" [ id "input", onSubmit PostMessage ]
            [ input [ onInput TypeMessage, value model.typing ] []
            , button [] [ text "Send" ]
            ]
        ]

messageActionView : Model -> Html Msg
messageActionView model =
    if List.any .selected model.messages then
        let
            selectedMessages = List.filter .selected model.messages
            action = 
                case model.cardMode of
                    Focused card _ ->
                        a [ onClick <| AddToCard card.id selectedMessages ]
                            [ text "add to card" ]
                    _ -> a [ onClick <| UnselectMessages ] [ text "unselect" ]
        in
            div [ id "messages-action" ]
                [ text <| (++)
                    (selectedMessages |> List.length |> toString)
                    " messages selected."
                , action
                ]
    else
        text ""

messageView : Dict String String -> Message -> Html Msg
messageView pictures message =
    let
        authorURL = case Dict.get message.author pictures of
            Nothing -> "https://api.adorable.io/avatars/140/" ++ message.author ++ ".png"
            Just url -> url
    in
        div
            [ class <| "message" ++ if message.selected then " selected" else ""
            , id message.id
            , on "click"
                <| JD.object1
                    (SelectMessage message.id)
                    ("shiftKey" := JD.bool)
            ]
            [ img [ src authorURL ] []
            , div []
                [ strong [] [ text message.author ]
                , div [ class "text" ] [ text message.text ]
                ]
            ]

cardsView : Model -> Html Msg
cardsView model =
  case model.cardMode of
    Focused card _ ->
        div [ id "fullcard" ]
            [ lazy2 fullCardView model.userPictures card
            , div [ class "back", onClick <| ClickCard "" ] []
            ]
    SearchResults query ids ->
        div [ id "searching" ] <|
            if List.length ids == 0 then
                [ h1 [] [ text <| "no cards were found for '" ++ query ++ "'." ] ]
            else
                [ h1 [] [ text <| "search results for '" ++ query ++ "':" ]
                , Keyed.node "div" [ id "cardlist" ]
                    (model.cards
                        |> List.filter (\c -> List.any ((==) c.id) ids)
                        |> List.map (\c -> (c.id, lazy briefCardView c))
                    )
                ]
    _ ->
        Keyed.node "div" [ id "cardlist" ]
            (model.cards
                |> List.take 10
                |> List.map (\c -> (c.id, lazy briefCardView c))
            )

briefCardView : Card -> Html Msg
briefCardView card =
    div [ class "card", id card.id ]
        [ div []
            [ b [ onClick <| ClickCard card.id ] [ text card.name ]
            , div [ class "contents" ]
                <| Array.toList
                <| Array.map (lazy briefCardContentView) card.contents
            ]
        ]

briefCardContentView : Content -> Html Msg
briefCardContentView content =
    case content of
        Text val ->
            div [] [ text val ]
        Conversation messages -> div [] [ text <| (List.length messages |> toString) ++ " messages" ]

fullCardView : Dict String String -> Card -> Html Msg
fullCardView userPictures card =
    div [ class "card", id card.id ]
        [ div []
            [ b [] [ text card.name ]
            ]
        , div [ class "contents" ]
            <| Array.toList
            <| Array.indexedMap (cardContentView userPictures card) card.contents
        , a
            [ class "add-content ion-more"
            , title "add text to this card"
            , onClick <| UpdateCardContents Add
            ] [ text "" ]
        ]

cardContentView : Dict String String -> Card -> Int -> Content -> Html Msg
cardContentView userPictures card index content =
    div [ class "content" ]
        [ case content of
            Text val ->
                div
                    [ class "text"
                    , contenteditable True
                    , on "blur"
                        <| JD.object1
                            (\v -> UpdateCardContents <| Edit index <| Text v)
                            (JD.at [ "target", "innerText" ] JD.string)
                    ] [ text val ]
            Conversation messages ->
                div [ class "conversation" ]
                    <| List.map (lazy2 messageView userPictures) messages
        , a
            [ class "delete ion-trash-a"
            , title "delete"
            , onClick <| UpdateCardContents <| Delete index
            ] [ text "" ]
        ]
