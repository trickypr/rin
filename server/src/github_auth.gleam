import envoy
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import model/user
import templates/mist_compat
import wisp

pub fn authorize() {
  let assert Ok(client_id) = envoy.get("GITHUB_CLIENT_ID")
  let assert Ok(redirect_uri) = envoy.get("GITHUB_REDIRECT_URI")
  wisp.redirect(
    to: "https://github.com/login/oauth/authorize?client_id="
    <> client_id
    <> "&redirect_uri="
    <> redirect_uri
    <> "&scope=user:email",
  )
}

type CallbackResponse {
  CallbackResponse(access_token: String, scope: String, token_type: String)
}

fn callback_decoder() {
  use access_token <- decode.field("access_token", decode.string)
  use scope <- decode.field("scope", decode.string)
  use token_type <- decode.field("token_type", decode.string)
  decode.success(CallbackResponse(access_token:, scope:, token_type:))
}

pub fn callback(req: wisp.Request) {
  let assert Ok(client_id) = envoy.get("GITHUB_CLIENT_ID")
  let assert Ok(client_secret) = envoy.get("GITHUB_CLIENT_SECRET")
  let result = {
    use code <- result.try(
      wisp.get_query(req)
      |> list.key_find("code")
      |> result.replace_error(CallbackErrorNoCode),
    )
    use req_base <- result.try(
      request.to("https://github.com/login/oauth/access_token")
      |> result.replace_error(CallbackErrorInternal("creating request")),
    )
    let req =
      req_base
      |> request.set_method(http.Post)
      |> request.prepend_header("Content-Type", "application/json")
      |> request.prepend_header("Accept", "application/json")
      |> request.set_body(
        json.object([
          #("client_id", json.string(client_id)),
          #("client_secret", json.string(client_secret)),
          #("code", json.string(code)),
        ])
        |> json.to_string,
      )

    use resp <- result.try(
      httpc.send(req) |> result.map_error(CallbackErrorHttp),
    )

    use _ <- result.try(case resp.status {
      200 -> Ok(Nil)
      _ -> Error(CallbackErrorExternal("Failure code, " <> resp.body))
    })

    use resp <- result.try(
      json.parse(resp.body, callback_decoder())
      |> result.replace_error(CallbackErrorInternal("Parsing body")),
    )

    use name <- result.try(get_name(resp.access_token))

    use user <- result.try(
      case user.get_by_name(name) {
        option.Some(res) -> res |> user.update_access_token(resp.access_token)
        option.None -> user.create(user.Github, name, resp.access_token)
      }
      |> result.map_error(io.debug)
      |> result.replace_error(CallbackErrorInternal("sqlite")),
    )

    Ok(user)
  }

  case result {
    Error(error) -> wisp.response(500) |> wisp.string_body(error_string(error))
    Ok(user) ->
      wisp.redirect("/")
      |> wisp.set_cookie(
        req,
        "user",
        user.to_json(user) |> json.to_string(),
        wisp.Signed,
        24 * 60 * 60,
      )
  }
}

fn github_request(path: String, access_token: String) {
  request.to("https://api.github.com" <> path)
  |> result.replace_error(CallbackErrorInternal("creating request"))
  |> result.map(fn(req) {
    req
    |> request.set_header("Authorization", "Bearer " <> access_token)
    |> request.set_header("User-Agent", "perms.dev")
    |> request.set_header("X-GitHub-Api-Version", "2022-11-28")
  })
  |> result.then(fn(req) {
    httpc.send(req) |> result.map_error(CallbackErrorHttp)
  })
}

fn get_name(access_token) {
  use req <- result.try(github_request("/user", access_token))
  json.parse(req.body, {
    use login <- decode.field("login", decode.string)
    decode.success(login)
  })
  |> result.replace_error(CallbackErrorInternal(
    "failed to decode user response",
  ))
}

type CallbackError {
  CallbackErrorNoCode
  CallbackErrorInternal(String)
  CallbackErrorExternal(String)
  CallbackErrorHttp(httpc.HttpError)
}

fn error_string(error: CallbackError) {
  case error {
    CallbackErrorExternal(str) -> "External error: " <> str
    CallbackErrorHttp(_) -> "http error"
    CallbackErrorInternal(str) -> "internal error: " <> str
    CallbackErrorNoCode -> "no code"
  }
}

pub fn has_auth(req: wisp.Request) {
  let cookie = wisp.get_cookie(req, "user", wisp.Signed)
  result.is_ok(cookie)
}

pub fn with_auth(req: wisp.Request) {
  let cookie = wisp.get_cookie(req, "user", wisp.Signed)

  case cookie {
    Ok(cookie) -> {
      let user = json.parse(from: cookie, using: user.user_decoder())
      case user {
        Ok(user) -> mist_compat.compat_continue(user)
        Error(_) -> mist_compat.compat_redirect("/auth/github")
      }
    }
    Error(_) -> mist_compat.compat_redirect("/auth/github")
  }
}
