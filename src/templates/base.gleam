import gleam/list
import lustre/attribute
import lustre/element
import lustre/element/html

const stylesheets = ["base.css", "tabs.css"]

pub fn base(head, body) {
  html.html([], [
    html.head(
      [],
      [
        html.script(
          [
            attribute.src(
              "https://cdn.jsdelivr.net/npm/petite-vue@0.4.1/dist/petite-vue.iife.js",
            ),
            attribute.attribute("defer", ""),
            attribute.attribute("init", ""),
          ],
          "",
        ),
      ]
        |> list.append(
          list.map(stylesheets, fn(stylesheet) {
            html.link([
              attribute.href("/static/" <> stylesheet),
              attribute.rel("stylesheet"),
            ])
          }),
        )
        |> list.append(head),
    ),
    html.body([], body),
  ])
  |> element.to_document_string_builder
}
