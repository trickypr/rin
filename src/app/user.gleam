import github_auth
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element/html
import model/project
import templates/base
import templates/error_pages
import wisp

pub fn project_list(request: wisp.Request) {
  use user <- github_auth.with_auth(request)
  use projs <- error_pages.internal_error(project.get_for_users(user))

  wisp.ok()
  |> wisp.html_body(base.base(
    [html.title([], "User Projects")],
    list.map(projs, fn(proj) {
      html.a([attribute.href("/projects/" <> int.to_string(proj.id))], [
        html.text(proj.id |> int.to_string()),
      ])
    }),
  ))
}
