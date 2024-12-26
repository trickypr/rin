import gleam/io
import gleam/option
import lustre/element/html
import templates/base
import wisp

pub fn internal_error(error: Result(a, b), continue) {
  case error {
    Ok(v) -> continue(v)
    Error(error) -> {
      io.debug(error)

      wisp.response(400)
      |> wisp.html_body(
        base.base([], [html.h1([], [html.text("Internal server error")])]),
      )
    }
  }
}

pub fn not_found(name: String, resource: option.Option(a), continue) {
  case resource {
    option.Some(found) -> continue(found)
    _ ->
      wisp.not_found()
      |> wisp.html_body(
        base.base([], [html.h1([], [html.text("Could not find " <> name)])]),
      )
  }
}
