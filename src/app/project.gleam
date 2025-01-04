import app/live
import github_auth
import gleam/dict
import gleam/http
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/regexp
import gleam/result
import gleam/string_tree
import gleroglero/outline
import lustre/attribute
import lustre/element/html
import model/modules
import model/project
import model/user
import templates/base
import templates/error_pages.{internal_error, not_found}
import templates/form
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
    [] -> project_editor(project, user)
    ["view"] -> project_view(project)
    ["publish"] -> project_update_host(req, project)

    ["head"] -> update_fn(project.Head)
    ["body"] -> update_fn(project.Body)
    ["css"] -> update_fn(project.CSS)
    ["js"] -> update_fn(project.JS)

    _ -> wisp.not_found()
  }
}

fn project_editor(project: project.Project, user: user.User) {
  let project.Project(id, _, head, body, css, js, modules, host, path) = project

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
            attribute.attribute("async", ""),
            attribute.attribute("defer", ""),
          ],
          "",
        ),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/css/editor.css"),
        ]),
        html.script(
          [
            attribute.src(
              "https://cdn.jsdelivr.net/npm/htmx.org@2.0.4/dist/htmx.min.js",
            ),
            attribute.attribute("crossorigin", "anonymous"),
          ],
          "",
        ),
      ],
      [
        tabs.tabs("editor", [
          tabs.Tab("Body", tabs.Name, [editor("body", body)], [
            tabs.Position(tabs.Left),
            tabs.NoStyle,
          ]),
          tabs.Tab("Head", tabs.Name, [editor("head", head)], [
            tabs.Position(tabs.Left),
            tabs.NoStyle,
          ]),
          tabs.Tab("CSS", tabs.Name, [editor("css", css)], [
            tabs.Position(tabs.Left),
            tabs.NoStyle,
          ]),
          tabs.Tab("JS", tabs.Name, [editor("js", js)], [
            tabs.Position(tabs.Left),
            tabs.NoStyle,
          ]),
          tabs.Tab(
            "Dependancies",
            tabs.Icon(outline.cube()),
            [
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
            ],
            [tabs.Position(tabs.Right)],
          ),
          tabs.Tab(
            "Publish",
            tabs.Icon(outline.globe_asia_australia()),
            [
              form.form(
                form.Auto(
                  "/projects/" <> int.to_string(project.id) <> "/publish",
                ),
                [
                  form.Text(
                    "host",
                    "Host",
                    "The host name of your domain. Must have a CNAME record pointing to `akropolis.trickypr.com`. You may use `"
                      <> user.name
                      <> ".pages.perm.dev`",
                    [
                      attribute.required(True),
                      attribute.value(host |> option.unwrap("")),
                      attribute.pattern(
                        "[a-zA-Z0-9][a-zA-Z0-9\\-\\.]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}",
                      ),
                    ],
                  ),
                  form.Text(
                    "path",
                    "Path",
                    "The path at the end of this domain that the url will be visible on",
                    [
                      attribute.required(False),
                      attribute.value(path |> option.unwrap("")),
                      attribute.placeholder("/"),
                    ],
                  ),
                ],
              ),
            ],
            [tabs.Position(tabs.Right)],
          ),
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

pub fn project_static(project: project.Project) {
  wisp.ok()
  |> wisp.html_body(
    {
      "<!doctype html><html><head>"
      <> project_view_head(project)
      <> "</head><body>"
      <> project_view_body(project, "static")
      <> "</body></html>"
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

type UpdateHost {
  UpdateHost(host: String, path: String)
}

fn form_value(form: wisp.FormData, search_key: String) {
  form.values
  |> list.find_map(fn(value) {
    let #(key, value) = value
    case search_key == key {
      True -> Ok(value)
      False -> Error(Nil)
    }
  })
}

fn validate_host(path: String) {
  let assert Ok(host_regex) =
    regexp.from_string(
      "[a-zA-Z0-9][a-zA-Z0-9\\-\\.]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}",
    )

  case regexp.check(host_regex, path) {
    False -> {
      io.println("Failed host validation")
      Error(Nil)
    }
    True -> Ok(path)
  }
}

fn project_update_host(req, project: project.Project) {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_form(req)

  // TODO: Validate host for user
  use host <- try_wisp(
    form_value(body, "host") |> result.try(validate_host) |> internal_error,
  )
  use body <- try_wisp(form_value(body, "path") |> internal_error)
  use _ <- try_wisp(
    project.update_publish(project, Some(host), Some(body)) |> internal_error,
  )

  wisp.ok()
}
