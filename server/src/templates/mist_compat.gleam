import gleam/bytes_tree
import gleam/http/response
import gleam/string_tree
import mist
import wisp

pub type CompatResult(v) {
  CompatContinue(v)
  CompatResult(code: Int, body: string_tree.StringTree)
  CompatRedirect(String)
}

pub fn compat_continue(v) {
  CompatContinue(v)
}

pub fn compat_result(code: Int, body: string_tree.StringTree) {
  CompatResult(code, body)
}

pub fn compat_redirect(location: String) {
  CompatRedirect(location)
}

pub fn try_wisp(compat, callback) {
  case compat {
    CompatContinue(v) -> callback(v)
    CompatResult(code, body) -> code |> wisp.response |> wisp.html_body(body)
    CompatRedirect(location) -> location |> wisp.redirect
  }
}

pub fn try_mist(compat, callback) {
  case compat {
    CompatContinue(v) -> callback(v)
    CompatResult(code, body) ->
      code
      |> response.new
      |> response.set_body(body |> bytes_tree.from_string_tree |> mist.Bytes)
    CompatRedirect(location) ->
      location
      |> response.redirect
      |> response.set_body(bytes_tree.new() |> mist.Bytes)
  }
}
