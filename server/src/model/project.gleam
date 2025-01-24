import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/http/request
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import model/database
import model/modules
import model/user
import sqlight
import templates/error_pages

pub type Project {
  Project(
    id: Int,
    owner_id: Int,
    head: String,
    body: String,
    css: String,
    js: String,
    modules: modules.Modules,
    host: Option(String),
    path: Option(String),
  )
}

pub type ProjectError {
  DatabaseError(sqlight.Error)
  ScriptParseError
}

fn query(query: String, values) {
  use conn <- database.get()
  let sql = "
    select id, owner_id, head, body, css, js, modules, host, path
    from projects
    where 
    " <> query

  use res <- result.try(
    sqlight.query(sql, on: conn, with: values, expecting: fn(dyn) {
      decode.run(dyn, {
        use id <- decode.field(0, decode.int)
        use owner_id <- decode.field(1, decode.int)
        use head <- decode.field(2, decode.string)
        use body <- decode.field(3, decode.string)
        use css <- decode.field(4, decode.string)
        use js <- decode.field(5, decode.string)
        use modules <- decode.field(6, modules.decoder())
        use host <- decode.field(7, decode.optional(decode.string))
        use path <- decode.field(8, decode.optional(decode.string))

        let modules =
          modules
          |> result.map_error(io.debug)
          |> result.replace_error(dict.new())
          |> result.unwrap_both()

        decode.success(Project(
          id:,
          owner_id:,
          head:,
          body:,
          css:,
          js:,
          modules:,
          host:,
          path:,
        ))
      })
      |> result.map_error(fn(errors) {
        errors
        |> list.map(fn(err) {
          let decode.DecodeError(expected, found, path) = err
          dynamic.DecodeError(expected, found, path)
        })
      })
    }),
  )

  Ok(res)
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

fn update_modules(project: Project, modules) {
  Project(..project, modules:)
}

pub fn update_content(project: Project, type_: UpdateType, content: String) {
  use conn <- database.get()
  let sql =
    "update projects set "
    <> update_type_to_column(type_)
    <> " = ? where id = ?"
  use _ <- result.try(
    sqlight.query(
      sql,
      on: conn,
      with: [sqlight.text(content), sqlight.int(project.id)],
      expecting: dynamic.element(0, dynamic.optional(dynamic.int)),
    )
    |> result.map_error(DatabaseError),
  )

  let modules = case type_ {
    JS -> {
      use imports <- result.try(
        modules.parse_imports(content) |> result.replace_error(ScriptParseError),
      )

      let new_deps = modules.new_deps(imports, project.modules)
      let #(new_modules, removed_deps) =
        new_deps
        |> dict.merge(project.modules)
        |> modules.cleanup(imports, _)

      "update projects set modules = ? where id = ?"
      |> sqlight.query(
        on: conn,
        with: [
          sqlight.text(
            new_modules
            |> modules.encoder
            |> json.to_string,
          ),
          sqlight.int(project.id),
        ],
        expecting: dynamic.element(0, dynamic.optional(dynamic.int)),
      )
      |> result.map_error(DatabaseError)
      |> result.replace(#(new_modules, new_modules, removed_deps))
    }
    _ -> Ok(#(project.modules, dict.new(), dict.new()))
  }

  let #(module_update, added, removed) =
    modules
    |> result.map(fn(input) { #(update_modules(_, input.0), input.1, input.2) })
    |> result.map_error(io.debug)
    |> result.replace_error(#(function.identity, dict.new(), dict.new()))
    |> result.unwrap_both

  let project =
    project
    |> module_update
    |> update_type_content(type_, content)

  Ok(#(project, added, removed))
}

pub fn update_publish(
  project: Project,
  host: Option(String),
  path: Option(String),
) {
  use conn <- database.get()
  let sql = "update projects set host = ?, path = ? where id = ?"
  use _ <- result.try(
    sqlight.query(
      sql,
      on: conn,
      with: [
        sqlight.nullable(sqlight.text, host),
        sqlight.nullable(sqlight.text, path),
        sqlight.int(project.id),
      ],
      expecting: dynamic.element(0, dynamic.optional(dynamic.int)),
    )
    |> result.map_error(DatabaseError),
  )

  Project(..project, host:, path:)
  |> Ok
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

pub fn get_for_host(host: String) {
  query("host = ?", [sqlight.text(host)])
}

pub fn create(user: user.User) {
  io.debug(user)
  use conn <- database.get()
  let sql = "insert into projects (owner_id) values (?) returning id"
  use id <- result.try(sqlight.query(
    sql,
    on: conn,
    with: [sqlight.int(user.id)],
    expecting: dynamic.element(0, dynamic.int),
  ))
  id |> list.first() |> result.unwrap(-1) |> Ok
}

pub fn matches_path(project: Project, target: List(String)) {
  project.path
  |> option.map(fn(path) {
    request.new() |> request.set_path(path) |> request.path_segments == target
  })
  |> option.unwrap(False)
}

pub fn owner_gate(project: Project, user: user.User) {
  case project.owner_id == user.id {
    True -> option.Some(Nil)
    False -> option.None
  }
  |> error_pages.not_found("project", _)
}
