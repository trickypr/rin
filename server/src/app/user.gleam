import github_auth
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element/html
import model/project
import templates/base
import templates/error_pages.{internal_error}
import templates/mist_compat.{try_wisp}
import wisp

pub fn project_list(request: wisp.Request) {
  use user <- try_wisp(github_auth.with_auth(request))
  use projs <- try_wisp(internal_error(project.get_for_users(user)))

  wisp.ok()
  |> wisp.html_body(
    base.base([html.title([], "User Projects")], [
      html.a([attribute.href("/projects/create")], [html.text("Create new")]),
      ..list.map(projs, fn(proj) {
        html.a([attribute.href("/projects/" <> int.to_string(proj.id))], [
          html.text(proj.id |> int.to_string()),
        ])
      })
    ]),
  )
}
