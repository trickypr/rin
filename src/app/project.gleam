import app/project_store.{type ProjectStore, StoreProject}
import github_auth
import gleam/erlang/process
import gleam/function
import gleam/http/response
import gleam/int
import gleam/io
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string_tree
import lustre/attribute
import lustre/element/html
import mist
import model/project
import templates/base
import templates/error_pages
import templates/tabs
import wisp.{type Request}

pub fn handle_project_request(
  req,
  id: String,
  rest: List(String),
  store: ProjectStore,
) {
  use id <- error_pages.internal_error(int.parse(id))
  use user <- github_auth.with_auth(req)
  use project <- error_pages.not_found("project", project.get_by_id(id))
  use <- project.owner_gate(project, user)

  let update_fn = update(req, project, _)

  case rest {
    [] -> project_editor(project)
    ["view"] -> project_view(project)

    ["head"] -> update_fn(project.Head)
    ["body"] -> update_fn(project.Body)
    ["css"] -> update_fn(project.CSS)
    ["js"] -> update_fn(project.JS)

    _ -> wisp.not_found()
  }
}

fn project_editor(project: project.Project) {
  let project.Project(id, _, head, body, css, js) = project

  let editor = fn(type_: String, content: String) {
    html.div(
      [attribute.class("editor"), attribute.attribute("data-type", type_)],
      [html.pre([], [html.text(content)])],
    )
  }

  wisp.ok()
  |> wisp.html_body(
    base.base(
      [
        html.title([], "Project"),
        html.script(
          [
            attribute.src("/bundled/editor.js"),
            attribute.type_("module"),
            attribute.attribute("defer", ""),
          ],
          "",
        ),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/css/editor.css"),
        ]),
      ],
      [
        tabs.tabs("editor", [
          tabs.Tab("Head", [editor("head", head)]),
          tabs.Tab("Body", [editor("body", body)]),
          tabs.Tab("CSS", [editor("css", css)]),
          tabs.Tab("JS", [editor("js", js)]),
        ]),
        html.div([attribute.class("preview__container")], [
          html.iframe([
            attribute.class("preview"),
            attribute.src("/projects/" <> int.to_string(id) <> "/view"),
          ]),
        ]),
      ],
    ),
  )
}

pub fn project_view_head(head: String, css: String) {
  head <> "<style>" <> css <> "</style>"
}

pub fn project_view_body(body: String, js: String, insertion: String) {
  body
  <> "<script type=\"module\" data-from=\""
  <> insertion
  <> "\">"
  <> js
  <> "</script>"
}

fn project_view(project: project.Project) {
  let project.Project(_, _, head, body, css, js) = project

  wisp.ok()
  |> wisp.html_body(
    {
      "<!doctype html><html><head>"
      <> project_view_head(head, css)
      <> "</head><body>"
      <> project_view_body(body, js, "static")
      <> "<script type=\"module\" src=\"/bundled/hot.js\" defer async></script></body></html>"
    }
    |> string_tree.from_string,
  )
}

fn update(req: Request, project: project.Project, update: project.UpdateType) {
  use body <- wisp.require_string_body(req)
  case project.update_content(project, update, body) {
    // TODO: Realtime updates
    Ok(_) -> wisp.ok()
    Error(_) -> wisp.internal_server_error()
  }
}

pub type HotState {
  HotState(pid: process.Pid)
}

pub type HotEvent {
  HeadUpdate(String)
  BodyUpdate(String)
  Down(process.ProcessDown)
}

pub fn project_hot(store: ProjectStore, req, id: String) {
  let project = process.call(store, StoreProject(id, _), 10)

  mist.server_sent_events(
    req,
    response.new(200)
      |> response.set_header("Access-Control-Allow-Origin", "*"),
    init: fn() {
      let subj = process.new_subject()
      let pid = process.self()
      let monitor = process.monitor_process(pid)
      let selector =
        process.new_selector()
        |> process.selecting(subj, function.identity)
        |> process.selecting_process_down(monitor, Down)

      process.send(
        project,
        project_store.ProjectAddListener(
          pid,
          fn(head, css) {
            process.send(subj, HeadUpdate(project_view_head(head, css)))
          },
          fn(body, js) {
            process.send(subj, BodyUpdate(project_view_body(body, js, "hot")))
          },
        ),
      )

      actor.Ready(HotState(pid), selector)
    },
    loop: fn(message, conn, state) {
      let send = fn(event: mist.SSEEvent) {
        event
        |> mist.send_event(conn, _)
        |> result.map(fn(_) { actor.continue(state) })
        |> result.map_error(fn(_) {
          io.println_error("Failed to send message")
          process.send(project, project_store.ProjectRemoveListener(state.pid))
          actor.Stop(process.Normal)
        })
        |> result.unwrap_both
      }

      case message {
        HeadUpdate(str) ->
          mist.event(string_tree.from_string(str))
          |> mist.event_name("head")
          |> send
        BodyUpdate(str) ->
          mist.event(string_tree.from_string(str))
          |> mist.event_name("body")
          |> send

        Down(_) -> {
          process.send(project, project_store.ProjectRemoveListener(state.pid))
          actor.Stop(process.Normal)
        }
      }

      actor.continue(state)
    },
  )
}
