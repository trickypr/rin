import envoy
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/result
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

    // TODO: Insert into database
    io.debug(resp)

    Ok(Nil)
  }

  case result {
    Error(error) -> wisp.response(500) |> wisp.string_body(error_string(error))
    Ok(_) -> wisp.redirect("/")
  }
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
