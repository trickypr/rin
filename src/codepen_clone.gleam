import gleam/erlang/process
import gleam/io
import mist
import radiate
import wisp.{type Request, type Response}
import wisp/wisp_mist

import app/project

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
  static_dir: String,
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

  use <- wisp.serve_static(req, under: "/static", from: static_dir)

  // Handle the request!
  handle_request(req)
}

fn handle_request(
  project_store: project.ProjectStore,
  static_dir: String,
  req: Request,
) -> Response {
  use _req <- middleware(req, static_dir)

  case wisp.path_segments(req) {
    ["project", id] -> project.project(project_store, req, id)
    ["project", id, "view"] -> project.project_view(project_store, id)
    ["project", id, "body"] ->
      project.project_update(project_store, req, project.ProjectSetBody, id)
    ["project", id, "head"] ->
      project.project_update(project_store, req, project.ProjectSetHead, id)
    ["project", id, "css"] ->
      project.project_update(project_store, req, project.ProjectSetCSS, id)
    ["project", id, "js"] ->
      project.project_update(project_store, req, project.ProjectSetJS, id)
    _ -> wisp.not_found()
  }
}

pub fn main() {
  // Hot reloading
  let _ =
    radiate.new()
    |> radiate.add_dir("src")
    |> radiate.on_reload(fn(_state, path) {
      io.println("Reload because change in " <> path)
    })
    |> radiate.start()

  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)
  let assert Ok(project_store) = project.store_create()

  let assert Ok(_) =
    wisp_mist.handler(
      handle_request(project_store, static_directory(), _),
      secret_key_base,
    )
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}

fn static_directory() {
  let assert Ok(priv_directory) = wisp.priv_directory("codepen_clone")
  priv_directory <> "/static"
}
