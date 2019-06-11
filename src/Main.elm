port module Main exposing (Model, Msg(..), init, main, subscriptions, update, view)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Http exposing (Progress, emptyBody, header, jsonBody)
import Json.Decode as D
import Json.Encode as E
import Platform.Cmd
import Platform.Sub
import Set exposing (Set)
import Url
import Url.Builder as B
import Url.Parser as P exposing ((</>))


apiUrl : String
apiUrl =
    B.crossOrigin "http://localhost" [ "api", "v1" ] []


staticUrl : String
staticUrl =
    B.absolute [ "static" ] []


main =
    Browser.application
        { init = init
        , subscriptions = subscriptions
        , update = update
        , view = view
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    signIn SignIn



-- Ports


port signIn : (E.Value -> msg) -> Sub msg



-- MODEL


type alias Access =
    { id : Int
    , access_name : String
    }


type alias User =
    { id : Int
    , first_name : String
    , last_name : String
    , email : String
    , banner_id : Int
    , accesses : List Access
    }


type alias PartialUser =
    { first_name : Maybe String
    , last_name : Maybe String
    , banner_id : Maybe Int
    , email : Maybe String
    }


type alias SignInUser =
    { first_name : String
    , last_name : String
    , email : String
    , profile_url : String
    , id_token : String
    }


type SignInModel
    = SignedIn SignInUser
    | SignedOut
    | SignInFailure D.Error


type Route
    = Home
    | Users
    | UserDetail Int
    | NotFound


routeParser : P.Parser (Route -> a) a
routeParser =
    P.oneOf
        [ P.map Home P.top
        , P.map Users (P.s "users")
        , P.map UserDetail (P.s "users" </> P.int)
        ]


type Network a
    = Loading
    | Loaded a
    | NetworkError Http.Error


type alias UserId =
    Int


type alias Model =
    { navkey : Nav.Key
    , route : Route
    , signin : SignInModel
    , accesses : Network (List Access)
    , users : Dict UserId User
    , users_status : Network ()
    , user_edit : PartialUser
    , user_new_access : Maybe Int
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { navkey = key
      , route = Maybe.withDefault NotFound (P.parse routeParser url)
      , signin = SignedOut
      , accesses = Loading
      , users = Dict.empty
      , users_status = Loading
      , user_edit =
            { first_name = Nothing
            , last_name = Nothing
            , banner_id = Nothing
            , email = Nothing
            }
      , user_new_access = Nothing
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = SignIn E.Value
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | GotUsers (Result Http.Error (List User))
    | GotUser (Result Http.Error User)
    | EditUserFirstName String
    | ResetUserFirstName
    | EditUserLastName String
    | ResetUserLastName
    | EditUserBannerId Int
    | ResetUserBannerId
    | EditUserEmail String
    | ResetUserEmail
    | SubmitEditUser
    | Updated (Result Http.Error ())
    | StartRemoveAccess Access
    | FinishRemoveAccess (Result Http.Error (Maybe Int))
    | EditNewUserAccess (Maybe Int)
    | SubmitNewUserAccess


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SignIn user_json ->
            case D.decodeValue signedInUserDecoder user_json of
                Ok user ->
                    let
                        ( users_status, cmd ) =
                            loadData model.route (SignedIn user)
                    in
                    ( { model
                        | signin = SignedIn user
                        , users_status = Maybe.withDefault model.users_status users_status
                      }
                    , cmd
                    )

                Err e ->
                    ( { model | signin = SignInFailure e }, Cmd.none )

        GotUsers users_result ->
            ( case users_result of
                Ok users ->
                    { model
                        | users = Dict.fromList (List.map (\u -> ( u.id, u )) users)
                        , users_status = Loaded ()
                    }

                Err e ->
                    { model | users_status = NetworkError e }
            , Cmd.none
            )

        GotUser user_result ->
            ( case user_result of
                Ok user ->
                    { model
                        | users = Dict.insert user.id user model.users
                        , users_status = Loaded ()
                    }

                Err e ->
                    { model | users_status = NetworkError e }
            , Cmd.none
            )

        EditUserFirstName first_name ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | first_name = Just first_name } }, Cmd.none )

        ResetUserFirstName ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | first_name = Nothing } }, Cmd.none )

        EditUserLastName last_name ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | last_name = Just last_name } }, Cmd.none )

        ResetUserLastName ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | last_name = Nothing } }, Cmd.none )

        EditUserBannerId banner_id ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | banner_id = Just banner_id } }, Cmd.none )

        ResetUserBannerId ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | banner_id = Nothing } }, Cmd.none )

        EditUserEmail email ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | email = Just email } }, Cmd.none )

        ResetUserEmail ->
            let
                partial_user =
                    model.user_edit
            in
            ( { model | user_edit = { partial_user | email = Nothing } }, Cmd.none )

        SubmitEditUser ->
            ( { model
                | user_edit = PartialUser Nothing Nothing Nothing Nothing
                , users_status = Loading
              }
            , case model.signin of
                SignedIn user ->
                    case model.route of
                        UserDetail user_id ->
                            Http.request
                                { method = "PUT"
                                , headers = [ header "id_token" user.id_token ]
                                , url =
                                    B.relative
                                        [ apiUrl
                                        , "users"
                                        , String.fromInt user_id
                                        ]
                                        []
                                , body = jsonBody (partialUserEncoder model.user_edit)
                                , expect = Http.expectWhatever Updated
                                , timeout = Nothing
                                , tracker = Nothing
                                }

                        _ ->
                            Cmd.none

                _ ->
                    Cmd.none
            )

        Updated _ ->
            let
                ( users_status, cmd ) =
                    loadData model.route model.signin
            in
            ( { model | users_status = Maybe.withDefault model.users_status users_status }
            , cmd
            )

        StartRemoveAccess access ->
            ( { model | users_status = Loading }
            , case model.signin of
                SignedIn user ->
                    case model.route of
                        UserDetail user_id ->
                            Http.request
                                { method = "GET"
                                , headers = [ header "id_token" user.id_token ]
                                , url =
                                    B.relative [ apiUrl, "user_access/" ]
                                        [ B.string "access_id"
                                            ("exact," ++ String.fromInt access.id)
                                        , B.string "user_id"
                                            ("exact," ++ String.fromInt user_id)
                                        ]
                                , body = emptyBody
                                , expect =
                                    Http.expectJson
                                        FinishRemoveAccess
                                        (D.map List.head userAccessListDecoder)
                                , timeout = Nothing
                                , tracker = Nothing
                                }

                        _ ->
                            Cmd.none

                _ ->
                    Cmd.none
            )

        FinishRemoveAccess user_access_result ->
            ( { model | users_status = Loading }
            , case user_access_result of
                Ok user_access_id ->
                    case user_access_id of
                        Just id ->
                            case model.signin of
                                SignedIn user ->
                                    Http.request
                                        { method = "DELETE"
                                        , headers = [ header "id_token" user.id_token ]
                                        , url =
                                            B.relative
                                                [ apiUrl
                                                , "user_access/"
                                                , String.fromInt id
                                                ]
                                                []
                                        , body = emptyBody
                                        , expect = Http.expectWhatever Updated
                                        , timeout = Nothing
                                        , tracker = Nothing
                                        }

                                _ ->
                                    Cmd.none

                        Nothing ->
                            Cmd.none

                Err e ->
                    Cmd.none
            )

        EditNewUserAccess access_id ->
            case access_id of
                Just id ->
                    ( { model | user_new_access = Just id }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        SubmitNewUserAccess ->
            ( { model
                | user_new_access = Nothing
                , users_status = Loading
              }
            , case model.user_new_access of
                Just new_access ->
                    case model.signin of
                        SignedIn user ->
                            case model.route of
                                UserDetail user_id ->
                                    Http.request
                                        { method = "POST"
                                        , headers = [ header "id_token" user.id_token ]
                                        , url = B.relative [ apiUrl, "user_access/" ] []
                                        , body =
                                            jsonBody
                                                (E.object
                                                    [ ( "access_id", E.int new_access )
                                                    , ( "user_id", E.int user_id )
                                                    , ( "permission_level", E.null )
                                                    ]
                                                )
                                        , expect = Http.expectWhatever Updated
                                        , timeout = Nothing
                                        , tracker = Nothing
                                        }

                                _ ->
                                    Cmd.none

                        _ ->
                            Cmd.none

                Nothing ->
                    Cmd.none
            )

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.navkey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            case P.parse routeParser url of
                Nothing ->
                    ( { model | route = NotFound }, Cmd.none )

                Just route ->
                    let
                        ( users_status, cmd ) =
                            loadData route model.signin
                    in
                    ( { model
                        | route = route
                        , users_status = Maybe.withDefault model.users_status users_status
                      }
                    , cmd
                    )


loadData : Route -> SignInModel -> ( Maybe (Network ()), Cmd Msg )
loadData route signin =
    case route of
        Home ->
            ( Nothing, Cmd.none )

        Users ->
            case signin of
                SignedIn user ->
                    ( Just Loading
                    , Http.request
                        { method = "GET"
                        , headers = [ header "id_token" user.id_token ]
                        , url = B.relative [ apiUrl, "users/" ] []
                        , body = emptyBody
                        , expect = Http.expectJson GotUsers userListDecoder
                        , timeout = Nothing
                        , tracker = Nothing
                        }
                    )

                _ ->
                    ( Just Loading, Cmd.none )

        UserDetail user_id ->
            case signin of
                SignedIn user ->
                    ( Just Loading
                    , Http.request
                        { method = "GET"
                        , headers = [ header "id_token" user.id_token ]
                        , url =
                            B.relative [ apiUrl, "users", String.fromInt user_id ]
                                []
                        , body = emptyBody
                        , expect = Http.expectJson GotUser userDecoder
                        , timeout = Nothing
                        , tracker = Nothing
                        }
                    )

                _ ->
                    ( Just Loading, Cmd.none )

        NotFound ->
            ( Nothing, Cmd.none )


signedInUserDecoder : D.Decoder SignInUser
signedInUserDecoder =
    D.map5 SignInUser
        (D.field "first_name" D.string)
        (D.field "last_name" D.string)
        (D.field "email" D.string)
        (D.field "profile_url" D.string)
        (D.field "id_token" D.string)


userDecoder : D.Decoder User
userDecoder =
    D.map6 User
        (D.field "id" D.int)
        (D.field "first_name" D.string)
        (D.field "last_name" D.string)
        (D.field "email" D.string)
        (D.field "banner_id" D.int)
        (D.field "accesses" (D.list accessDecoder))


userListDecoder : D.Decoder (List User)
userListDecoder =
    D.field "users" (D.list userDecoder)


accessDecoder : D.Decoder Access
accessDecoder =
    D.map2 Access
        (D.field "id" D.int)
        (D.field "access_name" D.string)


userAccessDecoder : D.Decoder Int
userAccessDecoder =
    D.field "permission_id" D.int


userAccessListDecoder : D.Decoder (List Int)
userAccessListDecoder =
    D.field "entries" (D.list userAccessDecoder)


partialUserEncoder : PartialUser -> E.Value
partialUserEncoder user =
    E.object
        ([]
            |> (\l ->
                    case user.first_name of
                        Just first_name ->
                            ( "first_name", E.string first_name ) :: l

                        Nothing ->
                            l
               )
            |> (\l ->
                    case user.last_name of
                        Just last_name ->
                            ( "last_name", E.string last_name ) :: l

                        Nothing ->
                            l
               )
            |> (\l ->
                    case user.banner_id of
                        Just banner_id ->
                            ( "banner_id", E.int banner_id ) :: l

                        Nothing ->
                            l
               )
            |> (\l ->
                    case user.email of
                        Just email ->
                            ( "email", E.string email ) :: l

                        Nothing ->
                            l
               )
        )



-- VIEW


viewSignIn : SignInModel -> Html Msg
viewSignIn model =
    case model of
        SignedIn user ->
            span [ class "level" ]
                [ div [ class "level-left" ]
                    [ p [ class "has-text-left", class "level-item" ]
                        [ text (user.first_name ++ " " ++ user.last_name) ]
                    ]
                , div [ class "level-right" ]
                    [ div [ class "image is-32x32", class "level-item" ]
                        [ img [ src user.profile_url ] [] ]
                    ]
                ]

        SignedOut ->
            div [ class "level-item" ]
                [ div []
                    [ div
                        [ class "g-signin2"
                        , attribute "data-onsuccess" "onSignIn"
                        ]
                        [ text "Waiting for Google..." ]
                    ]
                ]

        SignInFailure _ ->
            div [] [ text "Failed to sign in" ]


viewUser : User -> Html Msg
viewUser user =
    a [ class "box", href (B.relative [ "users", String.fromInt user.id ] []) ]
        [ p [ class "title is-5" ] [ text (user.first_name ++ " " ++ user.last_name) ]
        , p [ class "subtitle is-5 columns" ]
            [ span [ class "column" ]
                [ text ("Email: " ++ user.email) ]
            , span [ class "column" ]
                [ text ("Banner ID: " ++ String.fromInt user.banner_id) ]
            ]
        ]


viewAccess : User -> Access -> Html Msg
viewAccess user access =
    div [ class "columns" ]
        [ span [ class "column" ] [ text (String.fromInt access.id ++ ": " ++ access.access_name) ]
        , div [ class "column" ]
            [ button
                [ class "button is-danger is-pulled-right"
                , onClick (StartRemoveAccess access)
                ]
                [ text "Remove" ]
            ]
        ]


viewEditableText : String -> Maybe String -> (String -> Msg) -> Msg -> Html Msg
viewEditableText defaultText editedText onEdit onReset =
    case editedText of
        Nothing ->
            p
                [ onClick (onEdit defaultText) ]
                [ text defaultText ]

        Just edited ->
            div [ class "field has-addons" ]
                [ div [ class "control" ]
                    [ input
                        [ class "input"
                        , value edited
                        , onInput onEdit
                        ]
                        []
                    ]
                , div [ class "control" ]
                    [ button
                        [ class "button is-danger"
                        , onClick onReset
                        ]
                        [ text "Reset" ]
                    ]
                ]


viewEditableInt : Int -> Maybe Int -> (Int -> Msg) -> Msg -> Html Msg
viewEditableInt default edited onEdit onReset =
    case edited of
        Nothing ->
            p
                [ onClick (onEdit default) ]
                [ text (String.fromInt default) ]

        Just edit ->
            div [ class "field has-addons" ]
                [ div [ class "control" ]
                    [ input
                        [ class "input"
                        , value (String.fromInt edit)
                        , onInput (\s -> onEdit (Maybe.withDefault 0 (String.toInt s)))
                        , type_ "number"
                        ]
                        []
                    ]
                , div [ class "control" ]
                    [ button
                        [ class "button is-danger"
                        , onClick onReset
                        ]
                        [ text "Reset" ]
                    ]
                ]


viewAddUserAccess : User -> Maybe Int -> Html Msg
viewAddUserAccess user access_id =
    case access_id of
        Nothing ->
            button
                [ class "button is-primary", onClick (EditNewUserAccess (Just 0)) ]
                [ text "Add" ]

        Just edit ->
            div [ class "field has-addons" ]
                [ div [ class "control" ]
                    [ input
                        [ class "input"
                        , value (String.fromInt edit)
                        , onInput (\s -> EditNewUserAccess (String.toInt s))
                        , type_ "number"
                        ]
                        []
                    ]
                , div [ class "control" ]
                    [ button
                        [ class "button is-primary"
                        , onClick SubmitNewUserAccess
                        ]
                        [ text "Submit" ]
                    ]
                ]


viewUserDetail : User -> PartialUser -> Maybe Int -> Network () -> Html Msg
viewUserDetail user user_edit user_new_access users_status =
    div []
        [ viewNetwork (\a -> div [] []) users_status
        , p [ class "title has-text-centered" ]
            [ text (user.first_name ++ " " ++ user.last_name) ]
        , p [ class "columns" ]
            [ span [ class "column" ]
                [ p [ class "subtitle has-text-centered" ] [ text "User Details" ]
                , div [ class "box" ]
                    [ span [] [ text "First Name: " ]
                    , viewEditableText
                        user.first_name
                        user_edit.first_name
                        EditUserFirstName
                        ResetUserFirstName
                    ]
                , div [ class "box" ]
                    [ span [] [ text "Last Name: " ]
                    , viewEditableText
                        user.last_name
                        user_edit.last_name
                        EditUserLastName
                        ResetUserLastName
                    ]
                , div [ class "box" ]
                    [ span [] [ text "Email: " ]
                    , viewEditableText
                        user.email
                        user_edit.email
                        EditUserEmail
                        ResetUserEmail
                    ]
                , div [ class "box" ]
                    [ span [] [ text "Banner ID: " ]
                    , viewEditableInt
                        user.banner_id
                        user_edit.banner_id
                        EditUserBannerId
                        ResetUserBannerId
                    ]
                , button
                    [ class "button is-primary"
                    , onClick SubmitEditUser
                    ]
                    [ text "Submit edits" ]
                ]
            , div [ class "column" ]
                [ p [ class "subtitle has-text-centered" ] [ text "User Permissions" ]
                , div [ class "box" ] (List.map (viewAccess user) user.accesses)
                , viewAddUserAccess user user_new_access
                ]
            ]
        ]


viewPageUserList : Dict UserId User -> Network () -> Html Msg
viewPageUserList users users_status =
    div []
        [ viewNetwork (\a -> div [] []) users_status
        , p [ class "title has-text-centered" ] [ text "Users" ]
        , div [ class "columns" ]
            [ div [ class "column is-one-fifth" ]
                [ p [ class "title is-4 has-text-centered" ] [ text "Search" ]
                , p [ class "has-text-centered" ] [ text "Working on it :)" ]
                ]
            , div [ class "column" ] (List.map viewUser (Dict.values users))
            ]
        ]


viewNetwork : (a -> Html Msg) -> Network a -> Html Msg
viewNetwork viewFunc network =
    case network of
        Loading ->
            progress [ class "progress is-info is-small" ] []

        Loaded a ->
            viewFunc a

        NetworkError e ->
            div [ class "notification is-danger" ]
                [ text "There was a problem with the network. The shown data may not be up to date." ]


viewNetwork2 : (a -> b -> Html Msg) -> Network a -> Network b -> Html Msg
viewNetwork2 viewFunc network_a network_b =
    case ( network_a, network_b ) of
        ( Loading, Loading ) ->
            div [] [ text "Loading..." ]

        ( Loading, Loaded a ) ->
            div [] [ text "Loading..." ]

        ( Loaded a, Loading ) ->
            div [] [ text "Loading..." ]

        ( Loaded a, Loaded b ) ->
            viewFunc a b

        ( NetworkError e, _ ) ->
            div [] [ text "Network error!" ]

        ( _, NetworkError e ) ->
            div [] [ text "Network error!" ]


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Users ->
            viewPageUserList model.users model.users_status

        UserDetail user_id ->
            case Dict.get user_id model.users of
                Just user ->
                    viewUserDetail user model.user_edit model.user_new_access model.users_status

                Nothing ->
                    p [] [ text "User not found" ]

        Home ->
            h1 [] [ text "Welcome to the A-Team!" ]

        NotFound ->
            h1 [] [ text "Page not found!" ]


view : Model -> Browser.Document Msg
view model =
    { title = "A-Team!"
    , body =
        [ div []
            [ nav [ class "navbar", class "is-primary" ]
                [ div [ class "navbar-brand" ]
                    [ a [ class "navbar-item", href "/" ]
                        [ img [ src (B.relative [ staticUrl, "logo.svg" ] []) ] [] ]
                    , a
                        [ attribute "role" "button"
                        , class "navbar-burger"
                        , class "burger"
                        , attribute "aria-label" "menu"
                        , attribute "aria-expanded" "false"
                        , attribute "data-target" "navbar"
                        ]
                        [ span [ attribute "aria-hidden" "true" ] []
                        , span [ attribute "aria-hidden" "true" ] []
                        , span [ attribute "aria-hidden" "true" ] []
                        ]
                    ]
                , div [ id "navbar", class "navbar-menu" ]
                    [ div [ class "navbar-start" ]
                        [ a [ class "navbar-item", href "/" ] [ text "Home" ]
                        , a [ class "navbar-item", href "/users" ] [ text "Users" ]
                        ]
                    , div [ class "navbar-end" ]
                        [ div [ class "navbar-item" ]
                            [ viewSignIn model.signin ]
                        ]
                    ]
                ]
            , div [ class "container" ] [ viewPage model ]
            ]
        ]
    }
