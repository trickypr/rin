import gleam/dict
import gleam/erlang/process
import gleam/function
import gleam/http/request
import gleam/int
import gleam/io
import gleam/option
import gleam/otp/actor
import gleam/result
import mist/internal/http
import model/project

import mist

pub opaque type Live {
  Live(subject: process.Subject(ProjectManagerMessage))
}

type ProjectManagerMessage {
  ProjectManagerSendSwap(
    project_id: Int,
    component: ProjectLiveSwap,
    value: String,
  )

  ProjectManagerRequsetListenerId(reply_with: process.Subject(Int))
  ProjectManagerRegisterSwapListener(
    project_id: Int,
    listener_id: Int,
    listener: fn(ProjectLiveSwap, String) -> Nil,
  )
  ProjectmanagerRemoveSwapListener(project_id: Int, listener_id: Int)
}

pub type ProjectLiveSwap {
  Head
  Body
}

fn live_swap_to_string(swap: ProjectLiveSwap) {
  case swap {
    Head -> "head"
    Body -> "body"
  }
}

type LiveState {
  LiveState(next_id: Int, projects: dict.Dict(Int, LiveProject))
}

type LiveProject {
  LiveProject(swaps: dict.Dict(Int, fn(ProjectLiveSwap, String) -> Nil))
}

fn clean(state) {
  LiveState(
    ..state,
    projects: state.projects
      |> dict.filter(fn(_, project) { project.swaps |> dict.size != 0 }),
  )
}

pub fn create() {
  use subject <- result.try(
    actor.start(
      LiveState(0, dict.new()),
      fn(message: ProjectManagerMessage, state) {
        let update_project = fn(project_id, update) {
          LiveState(
            ..state,
            projects: state.projects
              |> dict.insert(
                project_id,
                update(
                  dict.get(state.projects, project_id)
                  |> result.unwrap(LiveProject(dict.new())),
                ),
              ),
          )
        }

        case message {
          ProjectManagerRequsetListenerId(client) -> {
            process.send(client, state.next_id)
            LiveState(..state, next_id: state.next_id + 1)
          }
          ProjectManagerRegisterSwapListener(project_id, listener_id, listener) ->
            update_project(project_id, fn(project) {
              LiveProject(
                swaps: project.swaps |> dict.insert(listener_id, listener),
              )
            })
          ProjectmanagerRemoveSwapListener(project_id, listener_id) ->
            update_project(project_id, fn(project) {
              LiveProject(swaps: project.swaps |> dict.delete(listener_id))
            })
            |> clean
          ProjectManagerSendSwap(project_id, location, content) -> {
            let _ =
              state.projects
              |> dict.get(project_id)
              |> result.then(fn(project) {
                project.swaps
                |> dict.map_values(fn(_, swapper) { swapper(location, content) })
                Ok(Nil)
              })

            state
          }
        }
        |> actor.continue
      },
    ),
  )

  Ok(Live(subject:))
}

// =============================================================================
// Internal APIs for interfacing with the store

type ListenerId {
  ListenerId(inner: Int)
}

fn get_listener_id(live: Live) {
  let listener_id =
    process.call(live.subject, ProjectManagerRequsetListenerId, 10)
  ListenerId(listener_id)
}

fn add_swap_listener(
  live: Live,
  project_id: Int,
  listener: ListenerId,
  callback: fn(ProjectLiveSwap, String) -> Nil,
) {
  process.send(
    live.subject,
    ProjectManagerRegisterSwapListener(project_id, listener.inner, callback),
  )
}

fn remove_swap_listener(live: Live, project_id: Int, listener: ListenerId) {
  process.send(
    live.subject,
    ProjectmanagerRemoveSwapListener(project_id, listener.inner),
  )
}

// =============================================================================
// APIs exposed to code

type SocketState {
  SocketState(
    listener: ListenerId,
    subject: process.Subject(SocketSelectorMessage),
  )
}

type SocketSelectorMessage {
  SocketSwap(location: ProjectLiveSwap, content: String)
}

// Creates a websocket for sending live messages
// Websocket messages are structured as
//     <type> <param1> ... <content>
// Where type and parameters cannot contain spaces. There are a fixed number of
// params based on message type. Currently, there are:
// - `swap <param_location ("head" | "body")> <content>`
pub fn live_socket_request(
  request: request.Request(http.Connection),
  live: Live,
  project: project.Project,
) {
  mist.websocket(
    request:,
    on_init: fn(_conn) {
      let listener = get_listener_id(live)

      let subject = process.new_subject()
      let selector =
        process.new_selector() |> process.selecting(subject, function.identity)

      add_swap_listener(live, project.id, listener, fn(location, content) {
        process.send(subject, SocketSwap(location:, content:))
      })

      #(SocketState(listener:, subject:), option.Some(selector))
    },
    on_close: fn(state) {
      remove_swap_listener(live, project.id, state.listener)
    },
    handler: fn(state: SocketState, conn, msg) {
      case msg {
        mist.Custom(SocketSwap(location, content)) -> {
          let assert Ok(_) =
            mist.send_text_frame(
              conn,
              "swap " <> live_swap_to_string(location) <> " " <> content,
            )
          actor.continue(state)
        }
        mist.Text("ping") -> {
          let assert Ok(_) = mist.send_text_frame(conn, "pong")
          actor.continue(state)
        }
        mist.Binary(_) | mist.Text(_) -> actor.continue(state)
        mist.Shutdown | mist.Closed -> {
          actor.Stop(process.Normal)
        }
      }
    },
  )
}

pub fn send_swap_event(
  live: Live,
  project_id: Int,
  component: ProjectLiveSwap,
  content: String,
) {
  process.send(
    live.subject,
    ProjectManagerSendSwap(project_id, component, content),
  )
}
