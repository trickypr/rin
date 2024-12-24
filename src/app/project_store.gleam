import gleam/dict
import gleam/erlang/process
import gleam/otp/actor
import gleam/result

pub type ProjectStore =
  process.Subject(StoreMsg)

pub type StoreMsg {
  StoreProject(id: String, reply_with: process.Subject(ProjectActor))
}

pub fn store_create() {
  actor.start(dict.from_list([]), store_msg)
}

fn store_msg(msg: StoreMsg, state) {
  case msg {
    StoreProject(id, client) -> {
      let #(new_state, project) =
        find_or_insert(state, id, fn() {
          let assert Ok(project) = project_create()
          project
        })

      process.send(client, project)
      actor.continue(new_state)
    }
  }
}

// =============================================================================
// Single project

pub type ProjectListener {
  ProjectListener(
    /// (head, css)
    head_update: fn(String, String) -> Nil,
    /// (body, js)
    body_update: fn(String, String) -> Nil,
  )
}

pub type Project {
  Project(
    head: String,
    body: String,
    css: String,
    js: String,
    listeners: dict.Dict(process.Pid, ProjectListener),
  )
}

pub type ProjectMsg {
  ProjectGetCode(reply_with: process.Subject(#(String, String, String, String)))

  ProjectSetHead(String)
  ProjectSetBody(String)
  ProjectSetCSS(String)
  ProjectSetJS(String)

  ProjectRemoveListener(process.Pid)
  ProjectAddListener(
    process.Pid,
    head_update: fn(String, String) -> Nil,
    body_update: fn(String, String) -> Nil,
  )
}

pub type ProjectActor =
  process.Subject(ProjectMsg)

fn project_create() {
  actor.start(
    Project(
      "<title>Example project</title>",
      "<h1>Hello world!</h1>",
      "body { font-family: sans-serif; }",
      "",
      dict.new(),
    ),
    project_msg,
  )
}

fn project_msg(msg: ProjectMsg, state: Project) {
  let update = fn(change: String, update, notify) {
    let new_state = update(change)
    dict.each(state.listeners, fn(_pid, listener) {
      notify(listener, new_state)
    })
    actor.continue(new_state)
  }

  let update_body = fn(l: ProjectListener, s: Project) {
    l.body_update(s.body, s.js)
  }
  let update_head = fn(l: ProjectListener, s: Project) {
    l.head_update(s.head, s.css)
  }

  case msg {
    ProjectGetCode(client) -> {
      let Project(head, body, css, js, _) = state
      process.send(client, #(head, body, css, js))
      actor.continue(state)
    }

    ProjectSetBody(body) ->
      update(body, fn(b) { Project(..state, body: b) }, update_body)
    ProjectSetJS(js) ->
      update(js, fn(b) { Project(..state, css: b) }, update_body)
    ProjectSetCSS(css) ->
      update(css, fn(b) { Project(..state, css: b) }, update_head)
    ProjectSetHead(head) ->
      update(head, fn(b) { Project(..state, body: b) }, update_head)

    ProjectRemoveListener(pid) ->
      actor.continue(
        Project(
          ..state,
          listeners: dict.filter(state.listeners, fn(k, _v) { k != pid }),
        ),
      )
    ProjectAddListener(pid, head_update, body_update) ->
      actor.continue(
        Project(
          ..state,
          listeners: dict.insert(
            state.listeners,
            pid,
            ProjectListener(head_update, body_update),
          ),
        ),
      )
  }
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
