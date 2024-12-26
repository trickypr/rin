import github_auth
import gleam/erlang/process
import gleam/http/request
import gleam/io
import mist
import model/database
import radiate
import wisp.{type Request, type Response}
import wisp/wisp_mist

import app/project
import app/project_store

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
  project_store: project_store.ProjectStore,
  static_dir: String,
  bundled_dir: String,
  req: Request,
) -> Response {
  use _req <- middleware(req, static_dir, bundled_dir)

  case wisp.path_segments(req) {
    [] ->
      case github_auth.has_auth(req) {
        True -> wisp.ok()
        False -> wisp.redirect("/auth/github")
      }

    ["auth", "github"] -> github_auth.authorize()
    ["callback", "github"] -> github_auth.callback(req)

    ["project", id] -> project.project(project_store, id)
    ["project", id, "view"] -> project.project_view(project_store, id)
    ["project", id, "body"] ->
      project.project_update(
        project_store,
        req,
        project_store.ProjectSetBody,
        id,
      )
    ["project", id, "head"] ->
      project.project_update(
        project_store,
        req,
        project_store.ProjectSetHead,
        id,
      )
    ["project", id, "css"] ->
      project.project_update(
        project_store,
        req,
        project_store.ProjectSetCSS,
        id,
      )
    ["project", id, "js"] ->
      project.project_update(project_store, req, project_store.ProjectSetJS, id)
    _ -> wisp.not_found()
  }
}

fn handle_mist_request(wisp_handler, project_store) {
  fn(req) {
    case request.path_segments(req) {
      ["project", id, "view", "hot"] ->
        project.project_hot(project_store, req, id)
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
  let assert Ok(project_store) = project_store.store_create()

  let assert Ok(_) =
    wisp_mist.handler(
      handle_request(
        project_store,
        static_directory("css"),
        static_directory("bundled"),
        _,
      ),
      secret_key_base,
    )
    |> handle_mist_request(project_store)
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
