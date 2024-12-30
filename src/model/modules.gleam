import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/function
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/result
import gleam/set

import nibble.{do}
import nibble/lexer

// =============================================================================
// Modules model

pub type Modules =
  dict.Dict(String, ModuleInfo)

pub type ModuleInfo {
  ModuleInfo(version: option.Option(String))
}

fn module_info_decoder() {
  use version <- decode.field("version", decode.optional(decode.string))
  decode.success(ModuleInfo(version:))
}

pub fn decoder() {
  decode.string
  |> decode.map(fn(string) {
    json.parse(string, decode.dict(decode.string, module_info_decoder()))
  })
}

pub fn encoder(modules: Modules) {
  json.object(
    modules
    |> dict.to_list
    |> list.filter(fn(module) { module.0 != "" })
    |> list.map(fn(module) {
      let #(module, info) = module
      #(
        module,
        json.object([#("version", json.nullable(info.version, json.string))]),
      )
    }),
  )
}

pub fn to_import_map(modules: Modules) {
  let deps = modules |> dict.to_list |> list.map(fn(mod) { mod.0 })

  json.object([
    #(
      "imports",
      json.object(
        modules
        |> dict.to_list
        |> list.flat_map(fn(mod) {
          let url =
            "https://esm.sh/"
            <> mod.0
            <> {
              { mod.1 }.version
              |> option.map(fn(v) { "@" <> v })
              |> option.unwrap("")
            }
            <> list.filter(deps, fn(dep) { dep != mod.0 })
            |> list.reduce(fn(acc, x) { acc <> "," <> x })
            |> result.map(fn(x) { "?external=" <> x })
            |> result.unwrap("")

          [#(mod.0, json.string(url)), #(mod.0 <> "/", json.string(url <> "/"))]
        }),
      ),
    ),
  ])
  |> json.to_string
}

pub fn new_deps(imports: List(Import), modules: Modules) {
  // TODO: Make path dependancies not make this explode
  imports
  |> list.map(fn(imp) { #(imp.module_specifier, ModuleInfo(version: None)) })
  |> dict.from_list
  |> dict.filter(fn(key, _) { !dict.has_key(modules, key) })
}

/// Cleans up packages that are unused and do not have an assigned version
pub fn cleanup(imports: List(Import), modules: Modules) {
  let filter = fn(name, info: ModuleInfo) {
    option.is_some(info.version)
    || {
      list.find(imports, fn(imp) { imp.module_specifier == name })
      |> result.is_ok
    }
  }

  // TODO: Make path dependancies not make this explode
  #(
    modules |> dict.filter(filter),
    modules |> dict.filter(fn(n, i) { !filter(n, i) }),
  )
}

// ============================================================================= 
// Import parser

pub type NamedImportSpecifier {
  NamedImportSpecifier(name: String, rename: option.Option(String))
}

pub type ImportClause {
  ImportDefualtBinding(identifier: String)
  NameSpaceImport(name: String)
  NamedImports(specifiers: List(NamedImportSpecifier))
}

pub type Import {
  Import(module_specifier: String, clauses: List(ImportClause))
}

pub type ParseError(l, p) {
  LexerError(l)
  ParserError(p)
}

pub type Token {
  Str(String)
  Identifier(String)
  ImportToken
  FromToken
  AsToken
  Comma
  Semi
  Star
  OpenBrace
  CloseBrace
  /// A special token that tells the parser to ignore the last import token
  TriggerClear
}

fn js_list(entry: nibble.Parser(a, b, c), sep: nibble.Parser(d, b, c)) {
  nibble.loop([], fn(entries) {
    use result <- do(nibble.optional(entry))

    case result {
      None -> nibble.Break(entries) |> nibble.return
      Some(result) -> {
        use seperator <- do(nibble.optional(sep))
        case seperator {
          None -> nibble.Break([result, ..entries])
          Some(_) -> nibble.Continue([result, ..entries])
        }
        |> nibble.return
      }
    }
  })
  |> nibble.map(list.reverse)
}

pub type LexerMode {
  Pass
  Imp
}

fn import_lexer() {
  let assert Ok(import_skip) = regexp.from_string("^im?p?o?r?$")
  let assert Ok(line_comment_skip) = regexp.from_string("^\\/(?!\\*)\\/?.*?")
  let assert Ok(block_comment_skip) = regexp.from_string("^\\/\\*?.*?\\*")

  lexer.advanced(fn(mode: LexerMode) {
    case mode {
      Imp -> [
        lexer.string("'", Str) |> lexer.into(fn(_) { Pass }),
        lexer.string("\"", Str) |> lexer.into(fn(_) { Pass }),
        lexer.keyword("from", " ", FromToken),
        lexer.keyword("as", " ", AsToken),
        lexer.identifier("[\\w\\$_]", "[\\w\\d\\$_]", set.new(), Identifier),
        lexer.token("*", Star),
        lexer.token(",", Comma),
        lexer.token("{", OpenBrace),
        lexer.token("}", CloseBrace),
        // Drop things we have not handled so far
        lexer.whitespace(Nil) |> lexer.ignore,
      ]
      Pass -> [
        lexer.keyword("import", " ", ImportToken) |> lexer.into(fn(_) { Imp }),
        lexer.comment("//", fn(_) { Nil }) |> lexer.ignore,
        lexer.custom(fn(mode, current, next) {
          case
            regexp.check(import_skip, current)
            || { regexp.check(line_comment_skip, current) && next != "\n" }
            || { regexp.check(block_comment_skip, current) && next != "/" }
          {
            True -> lexer.Skip
            False -> lexer.Drop(mode)
          }
        }),
      ]
    }
  })
}

fn import_parser() {
  let string_parser =
    nibble.take_map("expected string", fn(tok) {
      case tok {
        Str(a) -> Some(a)
        _ -> None
      }
    })

  let comma_then = fn(parser) {
    use _ <- do(nibble.token(Comma))
    do(parser, nibble.return)
  }

  let identifier = fn(map: fn(String) -> a) {
    nibble.take_map("expected identifier", fn(tok) {
      case tok {
        Identifier(identifier) -> Some(map(identifier))
        _ -> None
      }
    })
  }

  let import_default_binding = identifier(ImportDefualtBinding)

  let name_space_import = {
    use _ <- do(nibble.token(Star))
    use _ <- do(nibble.token(AsToken))
    use name <- do(identifier(function.identity))
    nibble.return(NameSpaceImport(name))
  }

  let import_specifier = {
    use name <- do(identifier(function.identity))
    use rename <- do(
      nibble.optional({
        use _ <- do(nibble.token(AsToken))
        do(identifier(function.identity), nibble.return)
      }),
    )
    nibble.return(NamedImportSpecifier(name, rename))
  }

  let named_imports = {
    use _ <- do(nibble.token(OpenBrace))
    use names <- do(js_list(import_specifier, nibble.token(Comma)))
    use _ <- do(nibble.token(CloseBrace))

    nibble.return(NamedImports(names))
  }

  let import_clause_parser = {
    use default_binding: option.Option(ImportClause) <- do(nibble.optional(
      import_default_binding,
    ))

    use next: option.Option(ImportClause) <- do(
      default_binding
      |> option.map(fn(_) {
        nibble.one_of([name_space_import, named_imports])
        |> comma_then
        |> nibble.optional
      })
      |> option.unwrap(
        nibble.one_of([name_space_import, named_imports]) |> nibble.map(Some),
      ),
    )

    use _ <- do(nibble.token(FromToken))

    nibble.return(
      [default_binding, next] |> list.filter_map(option.to_result(_, Nil)),
    )
  }

  let import_parser = {
    use _ <- do(nibble.token(ImportToken))
    use import_clause <- do(nibble.optional(import_clause_parser))
    use module_specifier <- do(string_parser)
    use _ <- do(nibble.optional(nibble.token(Semi)))

    nibble.return(Import(
      module_specifier:,
      clauses: import_clause |> option.unwrap([]),
    ))
  }

  import_parser |> nibble.many
}

pub fn parse_imports(code: String) {
  let lexer = import_lexer()

  lexer.run_advanced(code, Pass, lexer)
  |> result.map_error(LexerError)
  |> result.try(fn(tokens) {
    nibble.run(tokens, import_parser()) |> result.map_error(ParserError)
  })
}
