import app/live
import github_auth
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string_tree
import lustre/attribute
import lustre/element/html
import model/modules
import model/project
import templates/base
import templates/error_pages.{internal_error, not_found}
import templates/mist_compat.{try_wisp}
import templates/tabs
import wisp.{type Request}

pub fn handle_project_request(
  req,
  id: String,
  rest: List(String),
  live: live.Live,
) {
  use id <- try_wisp(internal_error(int.parse(id)))
  use user <- try_wisp(github_auth.with_auth(req))
  use project <- try_wisp(not_found("project", project.get_by_id(id)))
  use _ <- try_wisp(project.owner_gate(project, user))

  let update_fn = update(live, req, project, _)

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
  let project.Project(id, _, head, body, css, js, modules) = project

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
          tabs.Tab("Dependancies", [
            html.ul(
              [],
              dict.to_list(modules)
                |> list.map(fn(module) {
                  let #(name, info) = module
                  html.li([], [
                    html.text(
                      name <> ": " <> option.unwrap(info.version, "latest"),
                    ),
                  ])
                }),
            ),
          ]),
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

fn project_view_head(project: project.Project) {
  project.head <> "<style>" <> project.css <> "</style>"
}

fn project_view_body(project: project.Project, insertion: String) {
  project.body
  <> "<script type=\"importmap\">"
  <> modules.to_import_map(project.modules)
  <> "</script><script type=\"module\" data-from=\""
  <> insertion
  <> "\">"
  <> project.js
  <> "</script>"
}

fn project_view(project: project.Project) {
  wisp.ok()
  |> wisp.html_body(
    {
      "<!doctype html><html><head>"
      <> project_view_head(project)
      <> "</head><body>"
      <> project_view_body(project, "static")
      <> "<script type=\"module\" src=\"/bundled/hot.js\" defer async></script></body></html>"
    }
    |> string_tree.from_string,
  )
}

fn update(
  live: live.Live,
  req: Request,
  project: project.Project,
  update: project.UpdateType,
) {
  use body <- wisp.require_string_body(req)
  case project.update_content(project, update, body) {
    Ok(#(project, deps_added, deps_removed)) -> {
      let #(location, content) = case update {
        project.Body -> #(live.Body, project_view_body(project, "hot"))
        project.JS -> #(live.Body, project_view_body(project, "hot"))
        project.CSS -> #(live.Head, project_view_head(project))
        project.Head -> #(live.Head, project_view_head(project))
      }
      live.send_swap_event(live, project.id, location, content)

      deps_added
      |> dict.keys
      |> list.map(live.send_dep_change(live, project.id, live.Add, _))
      deps_removed
      |> dict.keys
      |> list.map(live.send_dep_change(live, project.id, live.Remove, _))

      wisp.ok()
    }
    Error(_) -> wisp.internal_server_error()
  }
}
