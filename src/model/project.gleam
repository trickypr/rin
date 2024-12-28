import gleam/dynamic
import gleam/list
import gleam/option
import gleam/result
import model/database
import model/user
import sqlight
import templates/error_pages
import wisp

pub type Project {
  Project(
    id: Int,
    owner_id: Int,
    head: String,
    body: String,
    css: String,
    js: String,
  )
}

fn project_db_dynamic() {
  dynamic.tuple6(
    dynamic.int,
    dynamic.int,
    dynamic.string,
    dynamic.string,
    dynamic.string,
    dynamic.string,
  )
}

fn query(query: String, values) {
  use conn <- database.get()
  let sql = "
    select id, owner_id, head, body, css, js
    from projects
    where 
    " <> query

  use res <- result.try(sqlight.query(
    sql,
    on: conn,
    with: values,
    expecting: project_db_dynamic(),
  ))

  list.map(res, fn(param) {
    let #(id, owner_id, head, body, css, js) = param
    Project(id:, owner_id:, head:, body:, css:, js:)
  })
  |> Ok
}

pub type UpdateType {
  Head
  Body
  CSS
  JS
}

fn update_type_to_column(type_: UpdateType) {
  case type_ {
    Head -> "head"
    Body -> "body"
    CSS -> "css"
    JS -> "js"
  }
}

fn update_type_content(project: Project, type_: UpdateType, content: String) {
  case type_ {
    Head -> Project(..project, head: content)
    Body -> Project(..project, body: content)
    CSS -> Project(..project, css: content)
    JS -> Project(..project, js: content)
  }
}

pub fn update_content(project: Project, type_: UpdateType, content: String) {
  use conn <- database.get()
  let sql =
    "update projects set "
    <> update_type_to_column(type_)
    <> " = ? where id = ?"
  use _ <- result.try(sqlight.query(
    sql,
    on: conn,
    with: [sqlight.text(content), sqlight.int(project.id)],
    expecting: dynamic.element(0, dynamic.optional(dynamic.int)),
  ))

  update_type_content(project, type_, content) |> Ok
}

pub fn get_by_id(id: Int) {
  case query("id = ?", [sqlight.int(id)]) {
    Ok([project]) -> option.Some(project)
    _ -> option.None
  }
}

pub fn get_for_users(user: user.User) {
  query("owner_id = ?", [sqlight.int(user.id)])
}

pub fn owner_gate(project: Project, user: user.User) {
  case project.owner_id == user.id {
    True -> option.Some(Nil)
    False -> option.None
  }
  |> error_pages.not_found("project", _)
}
