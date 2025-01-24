import gleam/list
import gleroglero/outline
import lustre/attribute
import lustre/element/html

pub type Submission {
  Auto(String)
  Manual
}

pub type Input(a) {
  Text(
    server_name: String,
    label: String,
    description: String,
    attributes: List(attribute.Attribute(a)),
  )
}

fn input(input: Input(a)) {
  case input {
    Text(server_name, label, description, attributes) ->
      html.label([], [
        html.h4([], [html.text(label)]),
        html.p([], [html.text(description)]),
        html.input([
          attribute.type_("text"),
          attribute.name(server_name),
          ..attributes
        ]),
      ])
  }
}

pub fn info(message: String) {
  html.div([attribute.class("info")], [
    html.div([attribute.class("info__icon")], [outline.information_circle()]),
    html.div([], [html.text(message)]),
  ])
}

fn submission_attributes(submission: Submission) {
  case submission {
    Auto(url) -> [
      attribute.attribute("hx-post", url),
      attribute.attribute("hx-trigger", "keyup changed delay:500ms"),
      attribute.attribute("hx-swap", "none"),
    ]
    Manual -> todo
  }
}

pub fn form(submission: Submission, inputs: List(Input(a))) {
  html.div([attribute.class("form")], [
    case submission {
      Auto(_) -> info("Changes will be automaticlally applied")
      _ -> html.div([], [])
    },
    html.form(submission_attributes(submission), inputs |> list.map(input)),
  ])
}
