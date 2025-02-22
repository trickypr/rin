import app/live
import app/user
import envoy
import github_auth
import gleam/erlang/process
import gleam/http/request
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import mist
import model/database
import radiate
import simplifile
import wisp.{type Request, type Response}
import wisp/wisp_mist

import app/project
import model/project as project_model
import templates/error_pages.{internal_error, not_found}
import templates/mist_compat.{try_mist, try_wisp}

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

  case req.host {
    "defaultdev.trickypr.com" | "tricky-desktop" ->
      case wisp.path_segments(req) {
        [] ->
          case github_auth.has_auth(req) {
            True -> wisp.redirect("/projects")
            False -> wisp.redirect("/auth/github")
          }

        ["auth", "github"] -> github_auth.authorize()
        ["callback", "github"] -> github_auth.callback(req)

        ["projects"] -> user.project_list(req)
        ["check"] -> wisp.ok()

        ["projects", "create"] -> {
          io.debug("Create route")
          project.create(req)
        }
        ["projects", id, ..rest] ->
          project.handle_project_request(req, id, rest, live)
        _ -> wisp.not_found()
      }

    host -> {
      use possible_projects <- try_wisp(
        project_model.get_for_host(host) |> internal_error,
      )
      use found_project <- try_wisp(
        possible_projects
        |> list.map(io.debug)
        |> list.find(project_model.matches_path(_, wisp.path_segments(req)))
        |> option.from_result
        |> not_found("project", _),
      )

      project.project_static(found_project)
    }
  }
}

fn handle_mist_request(wisp_handler, live) {
  fn(req: request.Request(mist.Connection)) {
    let socket_fn = fn(id) {
      use id <- try_mist(internal_error(int.parse(id)))
      // TODO: Auth
      // use user <- try_mist(github_auth.with_auth(req))
      use project <- try_mist(not_found("project", project_model.get_by_id(id)))
      // use _ <- try_mist(project_model.owner_gate(project, user))
      live.live_socket_request(req, live, project)
    }

    case request.path_segments(req) {
      ["projects", id, "live"] -> socket_fn(id)
      ["projects", id, "view", "live"] -> socket_fn(id)
      _ -> wisp_handler(req)
    }
  }
}

pub fn main() {
  let _ =
    envoy.get("WEB_DIRECTORY")
    |> result.map(fn(_) { True })
    |> result.unwrap(False)
    |> Ok
    |> result.map(fn(is_nix) {
      case is_nix {
        False -> {
          let _ =
            radiate.new()
            |> radiate.add_dir("src")
            |> radiate.on_reload(fn(_state, path) {
              io.println("Reload because change in " <> path)
            })
            |> radiate.start()
          Nil
        }
        True -> Nil
      }
    })

  // Gleam code hot reloading
  let _ = wisp.configure_logger()
  database.setup()

  let assert Ok(secret_key_base) = envoy.get("JWT_SECRET")
  let assert Ok(live) = live.create()

  let wisp_handler =
    wisp_mist.handler(
      handle_request(live, web_directory("css"), web_directory("bundled"), _),
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
  let assert Ok(priv_directory) = wisp.priv_directory("rin")
  priv_directory <> "/" <> name
}

fn web_directory(name) {
  let assert Ok(web_directory) = envoy.get("WEB_DIRECTORY")
  web_directory <> "/" <> name
}
