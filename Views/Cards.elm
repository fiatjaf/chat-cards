module Views.Cards exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (..)
import Json.Decode as JD exposing ((:=))
import Json.Encode as JE
import String
import Array

import Types exposing (Model, Card, Message,
                       Content(..), CardMode(..), Editing(..))
import State exposing (Msg(..), Action(..))
import Views.Messages exposing (messageView)


cardsView : Model -> Html Msg
cardsView model =
  case model.cardMode of
    Focused card _ editing ->
        div [ id "fullcard" ]
            [ lazy2 fullCardView card editing
            , div [ class "back", onClick <| ClickCard "" ] []
            ]
    SearchResults cards ->
        div [ id "searching" ] <|
            [ b [] [ text <| "search results:" ]
            , Keyed.node "div" [ id "cardlist" ]
                (cards
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
        [ div [ class "name", onClick <| ClickCard card.id ]
            [ b [] [ text card.name ]
            , span [] [ text <| "#" ++ (String.right 5 card.id) ]
            ]
        , div [ class "contents" ]
            <| Array.toList
            <| Array.map (lazy briefCardContentView) card.contents
        ]

briefCardContentView : Content -> Html Msg
briefCardContentView content =
    case content of
        Note val ->
            div [] [ text val ]
        Conversation messages ->
            div [] [ text <| (List.length messages |> toString) ++ " messages" ]

fullCardView : Card -> Editing -> Html Msg
fullCardView card editing =
    div [ class "card", id card.id ]
        [ header []
            [ div [ class "name" ] <|
                case editing of
                    Name ->
                        [ input
                            [ on "blur"
                                <| JD.object1 StopEditing
                                    (JD.at [ "target", "value" ] JD.string)
                            , value card.name
                            ] [ text "" ]
                        ]
                    _ ->
                        [ b
                            [ onClick <| StartEditing Name
                            , if card.name == "" then
                                property "innerHTML" (JE.string "&nbsp;&nbsp;&nbsp;")
                              else style []
                            ] [ text card.name ]
                        , span [] [ text <| "#" ++ (String.right 5 card.id) ]
                        ]
            , a
                [ class "delete ion-trash-a"
                , title "delete"
                , onClick DeleteCard
                ] [ text "" ]
            ]
        , div [ class "contents" ]
            <| Array.toList
            <| Array.indexedMap (cardContentView card) card.contents
        , a
            [ class "add-content ion-plus-round"
            , title "add text to this card"
            , onClick <| UpdateCardContents Add
            ] [ text "" ]
        ]

cardContentView : Card -> Int -> Content -> Html Msg
cardContentView card index content =
    div [ class "content" ]
        [ case content of
            Note val ->
                div
                    [ class "text"
                    , contenteditable True
                    , on "blur"
                        <| JD.object1
                            (\v -> UpdateCardContents <| Edit index <|  Note v)
                            (JD.at [ "target", "innerText" ] JD.string)
                    ] [ text val ]
            Conversation messages ->
                div [ class "conversation" ]
                    <| List.map (lazy messageView) messages
        , a
            [ class "delete ion-trash-a"
            , title "delete"
            , onClick <| UpdateCardContents <| Delete index
            ] [ text "" ]
        ]
