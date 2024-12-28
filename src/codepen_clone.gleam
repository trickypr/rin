import app/live
import app/user
import github_auth
import gleam/erlang/process
import gleam/http/request
import gleam/int
import gleam/io
import mist
import model/database
import radiate
import wisp.{type Request, type Response}
import wisp/wisp_mist

import app/project
import model/project as project_model
import templates/error_pages.{internal_error, not_found}
import templates/mist_compat.{try_mist}

/// The middleware stack that the request handler uses. The stack is itself a
/// middleware function!
///
/// Middleware wrap each other, so the request travels through the stack from
/// top to bottom until it reaches the request handler, at which point the
/// response travels back up through the stack.
/// 
/// The middleware used here are the ones that are suitable for use in your
/// typical web application.
/// 
pub fn middleware(
  req: wisp.Request,
  css_dir: String,
  bundled_dir: String,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  // Permit browsers to simulate methods other than GET and POST using the
  // `_method` query parameter.
  let req = wisp.method_override(req)

  // Log information about the request and response.
  use <- wisp.log_request(req)

  // Return a default 500 response if the request handler crashes.
  use <- wisp.rescue_crashes

  // Rewrite HEAD requests to GET requests and return an empty body.
  use req <- wisp.handle_head(req)

  use <- wisp.serve_static(req, under: "/css", from: css_dir)
  use <- wisp.serve_static(req, under: "/bundled", from: bundled_dir)

  // Handle the request!
  handle_request(req)
}

fn handle_request(
  live: live.Live,
  static_dir: String,
  bundled_dir: String,
  req: Request,
) -> Response {
  use _req <- middleware(req, static_dir, bundled_dir)

  case wisp.path_segments(req) {
    [] ->
      case github_auth.has_auth(req) {
        True -> wisp.redirect("/projects")
        False -> wisp.redirect("/auth/github")
      }

    ["auth", "github"] -> github_auth.authorize()
    ["callback", "github"] -> github_auth.callback(req)

    ["projects"] -> user.project_list(req)

    ["projects", id, ..rest] ->
      project.handle_project_request(req, id, rest, live)
    _ -> wisp.not_found()
  }
}

fn handle_mist_request(wisp_handler, live) {
  fn(req: request.Request(mist.Connection)) {
    case request.path_segments(req) {
      ["projects", id, "view", "live"] -> {
        use id <- try_mist(internal_error(int.parse(id)))
        // TODO: Auth
        // use user <- try_mist(github_auth.with_auth(req))
        use project <- try_mist(not_found(
          "project",
          project_model.get_by_id(id),
        ))
        // use _ <- try_mist(project_model.owner_gate(project, user))
        live.live_socket_request(req, live, project)
      }
      _ -> wisp_handler(req)
    }
  }
}

pub fn main() {
  // Gleam code hot reloading
  let _ =
    radiate.new()
    |> radiate.add_dir("src")
    |> radiate.on_reload(fn(_state, path) {
      io.println("Reload because change in " <> path)
    })
    |> radiate.start()

  wisp.configure_logger()
  database.setup()

  let secret_key_base = wisp.random_string(64)
  let assert Ok(live) = live.create()

  let wisp_handler =
    wisp_mist.handler(
      handle_request(
        live,
        static_directory("css"),
        static_directory("bundled"),
        _,
      ),
      secret_key_base,
    )

  let assert Ok(_) =
    handle_mist_request(wisp_handler, live)
    |> mist.new
    |> mist.port(8080)
    |> mist.bind("0.0.0.0")
    |> mist.start_http

  process.sleep_forever()
}

fn static_directory(name) {
  let assert Ok(priv_directory) = wisp.priv_directory("codepen_clone")
  priv_directory <> "/" <> name
}
