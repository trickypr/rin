import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/io
import gleam/json
import gleam/list
import gleam/option
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
  )
}

pub type ProjectError {
  DatabaseError(sqlight.Error)
  ScriptParseError
}

fn query(query: String, values) {
  use conn <- database.get()
  let sql = "
    select id, owner_id, head, body, css, js, modules
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
      let new_modules =
        modules.new_deps(imports, project.modules)
        |> dict.merge(project.modules)

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
      |> result.replace(new_modules)
    }
    _ -> Ok(project.modules)
  }
  let module_update = case modules {
    Ok(m) -> update_modules(_, m)
    _ -> function.identity
  }

  project
  |> module_update
  |> update_type_content(type_, content)
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

pub fn owner_gate(project: Project, user: user.User) {
  case project.owner_id == user.id {
    True -> option.Some(Nil)
    False -> option.None
  }
  |> error_pages.not_found("project", _)
}
