import gleam/option
import gleeunit/should
import model/modules

pub fn module_specifier_test() {
  modules.parse_imports("import 'module-name';")
  |> should.be_ok
  |> should.equal([modules.Import(module_specifier: "module-name", clauses: [])])
}

pub fn module_specifier_double_quotes_test() {
  modules.parse_imports("import \"module-name\";")
  |> should.be_ok
  |> should.equal([modules.Import(module_specifier: "module-name", clauses: [])])
}

pub fn module_specifier_no_semi_test() {
  modules.parse_imports("import 'module-name'")
  |> should.be_ok
  |> should.equal([modules.Import(module_specifier: "module-name", clauses: [])])
}

pub fn module_default_test() {
  modules.parse_imports("import defaultExport from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.ImportDefualtBinding("defaultExport"),
    ]),
  ])
}

pub fn module_namespace_test() {
  modules.parse_imports("import * as name from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NameSpaceImport("name"),
    ]),
  ])
}

pub fn module_default_and_namespace_test() {
  modules.parse_imports("import defaultExport, * as name from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.ImportDefualtBinding("defaultExport"),
      modules.NameSpaceImport("name"),
    ]),
  ])
}

// ============================================================================= 
// named imports

pub fn module_no_named_import_test() {
  modules.parse_imports("import {  } from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([]),
    ]),
  ])
}

pub fn module_single_named_import_test() {
  modules.parse_imports("import { example1 } from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.None),
      ]),
    ]),
  ])
}

pub fn module_multiple_named_imports_test() {
  modules.parse_imports("import { example1, example2 } from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.None),
        modules.NamedImportSpecifier("example2", option.None),
      ]),
    ]),
  ])
}

pub fn module_multiple_named_imports_trailing_test() {
  modules.parse_imports("import { example1, example2, } from 'module-name';")
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.None),
        modules.NamedImportSpecifier("example2", option.None),
      ]),
    ]),
  ])
}

pub fn module_multiple_named_imports_alias_test() {
  modules.parse_imports(
    "import { example1 as renamed1, example2, } from 'module-name';",
  )
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.Some("renamed1")),
        modules.NamedImportSpecifier("example2", option.None),
      ]),
    ]),
  ])
}

// ============================================================================= 
// Integration

pub fn multi_integration_test() {
  modules.parse_imports(
    "
  import { example1 as renamed1, example2, } from 'module-name';
  import { example3, } from 'other';
  ",
  )
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.Some("renamed1")),
        modules.NamedImportSpecifier("example2", option.None),
      ]),
    ]),
    modules.Import(module_specifier: "other", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example3", option.None),
      ]),
    ]),
  ])
}

pub fn noisy_integration_test() {
  modules.parse_imports(
    "
  // this is a bunch of garbage
  import { example1 as renamed1, example2, } from 'module-name';
  // we have another import here
  import { example3, } from 'other';

  example3()

  /** import */
  import()
  ",
  )
  |> should.be_ok
  |> should.equal([
    modules.Import(module_specifier: "module-name", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example1", option.Some("renamed1")),
        modules.NamedImportSpecifier("example2", option.None),
      ]),
    ]),
    modules.Import(module_specifier: "other", clauses: [
      modules.NamedImports([
        modules.NamedImportSpecifier("example3", option.None),
      ]),
    ]),
  ])
}
