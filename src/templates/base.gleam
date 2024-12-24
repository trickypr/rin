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
        // This script defines some global helpers that are used in vue globals
        html.script(
          [],
          "
        window.getLocalState = ( name, def ) => {
          const value = localStorage.getItem('storeState__' + name) || `\"${def}\"`
          return JSON.parse(value)
        }
        window.setLocalState = ( name, value ) => localStorage.setItem('storeState__' + name, JSON.stringify(value))
      ",
        ),
      ]
        |> list.append(
          list.map(stylesheets, fn(stylesheet) {
            html.link([
              attribute.href("/css/" <> stylesheet),
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
