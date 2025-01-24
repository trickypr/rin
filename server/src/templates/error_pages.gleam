import gleam/io
import gleam/option
import lustre/element/html
import templates/base
import templates/mist_compat

pub fn internal_error(error: Result(a, b)) {
  case error {
    Ok(v) -> mist_compat.compat_continue(v)
    Error(error) -> {
      io.debug(error)
      mist_compat.compat_result(
        400,
        base.base([], [html.h1([], [html.text("Internal server error")])]),
      )
    }
  }
}

pub fn not_found(name: String, resource: option.Option(a)) {
  case resource {
    option.Some(found) -> mist_compat.compat_continue(found)
    option.None ->
      mist_compat.compat_result(
        404,
        base.base([], [html.h1([], [html.text("Could not find " <> name)])]),
      )
  }
}
