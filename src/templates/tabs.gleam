import gleam/list
import lustre/attribute
import lustre/element/html
import lustre/internals/vdom

pub type Tab(a) {
  Tab(name: String, contents: List(vdom.Element(a)))
}

pub fn tabs(tab_id: String, tabs: List(Tab(a))) {
  let assert Ok(first_tab) = list.first(tabs)
  let state_name = "'tabs__" <> tab_id <> "'"

  html.div(
    [
      attribute.id("tabs__container--" <> tab_id),
      attribute.attribute(
        "v-scope",
        "{ tab: getLocalState("
          <> state_name
          <> ", '"
          <> first_tab.name
          <> "') }",
      ),
      attribute.attribute(
        "v-effect",
        "setLocalState(" <> state_name <> ", tab)",
      ),
      attribute.class("tabs__container"),
    ],
    [
      html.div(
        [attribute.attribute("role", "tablist"), attribute.class("tabs")],
        list.map(tabs, fn(tab) {
          html.div(
            [
              // TODO: Proper tab accessibility
              attribute.attribute("role", "tab"),
              attribute.attribute("@click", "tab = '" <> tab.name <> "'"),
              attribute.attribute(":selected", "tab == '" <> tab.name <> "'"),
              attribute.attribute(
                ":aria-selected",
                "tab == '" <> tab.name <> "'",
              ),
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
