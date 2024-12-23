import gleam/dict
import gleam/erlang/process
import gleam/otp/actor
import gleam/result
import gleam/string_tree
import lustre/attribute
import lustre/element
import lustre/element/html
import templates/base
import templates/tabs
import wisp.{type Request}

pub type ProjectStore =
  process.Subject(StoreMsg)

pub fn store_create() {
  actor.start(dict.from_list([]), store_msg)
}

pub type StoreMsg {
  StoreProject(id: String, reply_with: process.Subject(ProjectActor))
}

fn find_or_insert(dict, key, creator) {
  dict.get(dict, key)
  |> result.map_error(fn(_) {
    let value = creator()
    #(dict.insert(dict, key, value), value)
  })
  |> result.map(fn(value) { #(dict, value) })
  |> result.unwrap_both
}

fn store_msg(msg: StoreMsg, state) {
  case msg {
    StoreProject(id, client) -> {
      let #(new_state, project) =
        find_or_insert(state, id, fn() {
          let assert Ok(project) =
            actor.start(
              Project(
                "<title>Example project</title>",
                "<h1>Hello world!</h1>",
                "body { font-family: sans-serif; }",
                "",
              ),
              project_msg,
            )
          project
        })

      process.send(client, project)
      actor.continue(new_state)
    }
  }
}

pub type Project {
  Project(head: String, body: String, css: String, js: String)
}

pub type ProjectMsg {
  ProjectGetCode(reply_with: process.Subject(#(String, String, String, String)))

  ProjectSetHead(String)
  ProjectSetBody(String)
  ProjectSetCSS(String)
  ProjectSetJS(String)
}

pub type ProjectActor =
  process.Subject(ProjectMsg)

fn project_msg(msg: ProjectMsg, state) {
  case msg {
    ProjectGetCode(client) -> {
      let Project(head, body, css, js) = state
      process.send(client, #(head, body, css, js))
      actor.continue(state)
    }

    ProjectSetHead(head) -> actor.continue(Project(..state, head: head))
    ProjectSetBody(body) -> actor.continue(Project(..state, body: body))
    ProjectSetCSS(css) -> actor.continue(Project(..state, css: css))
    ProjectSetJS(js) -> actor.continue(Project(..state, js: js))
  }
}

pub fn project(store: ProjectStore, req: Request, id: String) {
  let project = process.call(store, StoreProject(id, _), 10)
  let #(head, body, css, js) = process.call(project, ProjectGetCode, 10)

  let editor_class = attribute.class("editor")
  let editor_data = fn(type_: String) {
    attribute.attribute("data-type", type_)
  }

  wisp.ok()
  |> wisp.html_body(
    base.base(
      [
        html.title([], "Project"),
        html.script(
          [
            attribute.src("/static/editor.js"),
            attribute.type_("module"),
            attribute.attribute("defer", ""),
          ],
          "",
        ),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/static/editor.css"),
        ]),
      ],
      [
        tabs.tabs([
          tabs.Tab("Head", [
            html.div([editor_class, editor_data("head")], [html.text(head)]),
          ]),
          tabs.Tab("Body", [
            html.div([editor_class, editor_data("body")], [html.text(body)]),
          ]),
          tabs.Tab("CSS", [
            html.div([editor_class, editor_data("css")], [html.text(css)]),
          ]),
          tabs.Tab("JS", [
            html.div([editor_class, editor_data("js")], [html.text(js)]),
          ]),
        ]),
        html.div([attribute.class("preview__container")], [
          html.iframe([
            attribute.class("preview"),
            attribute.src("/project/" <> id <> "/view"),
          ]),
        ]),
      ],
    ),
  )
}

pub fn project_view(store: ProjectStore, id: String) {
  let project = process.call(store, StoreProject(id, _), 10)
  let #(head, body, css, js) = process.call(project, ProjectGetCode, 10)

  wisp.ok()
  |> wisp.html_body(
    {
      "<!doctype html><html><head>"
      <> head
      <> "<style>"
      <> css
      <> "</style></head><body>"
      <> body
      <> "<script type=\"module\">"
      <> js
      <> "</script></body></html>"
    }
    |> string_tree.from_string,
  )
}

pub fn project_update(
  store: ProjectStore,
  req: Request,
  update_msg: fn(String) -> ProjectMsg,
  id: String,
) {
  use body <- wisp.require_string_body(req)
  let project = process.call(store, StoreProject(id, _), 10)
  process.send(project, update_msg(body))
  wisp.ok()
}
