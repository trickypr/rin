import gleam/dynamic
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import model/database
import sqlight

pub type UserProvider {
  Github
}

fn user_provider_from_string(str: String) {
  case str {
    "github" -> Ok(Github)
    _ -> Error(Nil)
  }
}

fn user_provider_decoder() {
  decode.string
  |> decode.map(user_provider_from_string)
  |> decode.then(fn(s) {
    result.map(s, decode.success)
    |> result.replace_error(decode.failure(Github, "UserProviderType"))
    |> result.unwrap_both
  })
}

fn user_provider_to_string(provider: UserProvider) {
  case provider {
    Github -> "github"
  }
}

pub type User {
  User(id: Int, provider: UserProvider, name: String, access_token: String)
}

pub fn to_json(user: User) {
  json.object([
    #("id", json.int(user.id)),
    #("provider", json.string(user_provider_to_string(user.provider))),
    #("name", json.string(user.name)),
    #("access_token", json.string(user.access_token)),
  ])
}

pub fn user_decoder() {
  use id <- decode.field("id", decode.int)
  use provider <- decode.field("provider", user_provider_decoder())
  use name <- decode.field("name", decode.string)
  use access_token <- decode.field("access_token", decode.string)
  decode.success(User(id:, provider:, name:, access_token:))
}

fn user_db_dynamic() {
  dynamic.tuple4(dynamic.int, dynamic.string, dynamic.string, dynamic.string)
}

pub fn create(provider: UserProvider, name: String, access_token: String) {
  use conn <- database.get()

  use id <- result.try(
    "
    insert into users (provider, name, access_token)
    values (?, ?, ?)
    returning id
  "
    |> sqlight.query(
      on: conn,
      with: [user_provider_to_string(provider), name, access_token]
        |> list.map(sqlight.text),
      expecting: dynamic.element(0, dynamic.int),
    ),
  )

  Ok(User(
    id: id |> list.first() |> result.unwrap(-1),
    provider:,
    name:,
    access_token:,
  ))
}

pub fn get_by_name(name: String) {
  let users = {
    use conn <- database.get()
    use users <- result.try(
      "select id, provider, name, access_token from users where name = ?"
      |> sqlight.query(
        on: conn,
        with: [sqlight.text(name)],
        expecting: user_db_dynamic(),
      ),
    )

    users
    |> list.map(fn(params) {
      let #(id, provider, name, access_token) = params
      let assert Ok(provider) = user_provider_from_string(provider)
      User(id:, provider:, name:, access_token:)
    })
    |> Ok
  }

  case users {
    Error(error) -> {
      io.println_error("Failed to fetch user with database error")
      io.debug(error)
      option.None
    }

    Ok([user]) -> option.Some(user)
    _ -> option.None
  }
}

pub fn update_access_token(user: User, access_token: String) {
  use conn <- database.get()

  use _ <- result.try(
    "
    update users
    set access_token = ?
    where id = ?
  "
    |> sqlight.query(
      on: conn,
      with: [sqlight.text(access_token), sqlight.int(user.id)],
      expecting: dynamic.element(0, dynamic.optional(dynamic.int)),
    ),
  )

  Ok(User(..user, access_token:))
}
