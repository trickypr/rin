import gleam/io
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html

pub type TabPosition {
  Left
  Right
}

pub type Modifier {
  /// Remove styling and padding
  NoStyle
  Position(TabPosition)
  ContainerStyle(List(#(String, String)))
}

pub type TabLabel(a) {
  Name
  Icon(element.Element(a))
}

pub type Tab(a) {
  Tab(
    name: String,
    label: TabLabel(a),
    contents: List(element.Element(a)),
    modifiers: List(Modifier),
  )
}

fn has_modifier(tab: Tab(a), modifier: Modifier) {
  tab.modifiers |> list.find(fn(mod) { mod == modifier }) |> result.is_ok
}

fn tab_position_matches(tab: Tab(a), position: TabPosition) {
  tab.modifiers
  |> list.find_map(fn(mod) {
    case mod {
      Position(pos) -> Ok(pos)
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(Left)
  == position
}

fn tab(tab: Tab(a)) {
  html.div(
    [
      // TODO: Proper tab accessibility
      attribute.attribute("role", "tab"),
      attribute.attribute("@click", "tab = '" <> tab.name <> "'"),
      attribute.attribute(":selected", "tab == '" <> tab.name <> "'"),
      attribute.attribute(":aria-selected", "tab == '" <> tab.name <> "'"),
      attribute.class("tabs__tab"),
    ],
    [
      html.div([attribute.class("tabs__inner")], [
        case tab.label {
          Icon(icon) -> html.div([attribute.class("tabs__tab-icon")], [icon])
          Name -> html.text(tab.name)
        },
      ]),
    ],
  )
}

pub fn tabs(tab_id: String, tabs: List(Tab(a))) {
  let assert Ok(first_tab) = list.first(tabs)
  let state_name = "'tabs__" <> tab_id <> "'"

  io.println("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  io.debug(tabs)

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
        [
          attribute.attribute("role", "tablist"),
          attribute.class("tabs__alignment"),
        ],
        [
          html.div(
            [attribute.class("tabs")],
            tabs |> list.filter(tab_position_matches(_, Left)) |> list.map(tab),
          ),
          html.div(
            [attribute.class("tabs")],
            tabs |> list.filter(tab_position_matches(_, Right)) |> list.map(tab),
          ),
        ],
      ),
      ..list.map(tabs, fn(tab) {
        html.div(
          [
            attribute.attribute("v-show", "tab == '" <> tab.name <> "'"),
            attribute.class("tabs__content"),
            attribute.classes([
              #("tabs__tab--content", !has_modifier(tab, NoStyle)),
            ]),
            ..{
              tab.modifiers
              |> list.filter_map(fn(mod) {
                case mod {
                  ContainerStyle(style) -> Ok(attribute.style(style))
                  _ -> Error(Nil)
                }
              })
            }
          ],
          tab.contents,
        )
      })
    ],
  )
}
