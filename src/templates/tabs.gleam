import gleam/list
import lustre/attribute
import lustre/element/html
import lustre/internals/vdom

pub type Tab(a) {
  Tab(name: String, contents: List(vdom.Element(a)))
}

pub fn tabs(tabs: List(Tab(a))) {
  let assert Ok(first_tab) = list.first(tabs)

  html.div(
    [
      attribute.attribute("v-scope", "{ tab: '" <> first_tab.name <> "'}"),
      attribute.class("tabs__container"),
    ],
    [
      html.div(
        [attribute.class("tabs")],
        list.map(tabs, fn(tab) {
          html.div(
            [
              attribute.attribute("@click", "tab = '" <> tab.name <> "'"),
              attribute.attribute(":selected", "tab == '" <> tab.name <> "'"),
              attribute.class("tabs__tab"),
            ],
            [html.div([attribute.class("tabs__inner")], [html.text(tab.name)])],
          )
        }),
      ),
      ..list.map(tabs, fn(tab) {
        html.div(
          [
            attribute.attribute("v-show", "tab == '" <> tab.name <> "'"),
            attribute.class("tabs__content"),
          ],
          tab.contents,
        )
      })
    ],
  )
}
