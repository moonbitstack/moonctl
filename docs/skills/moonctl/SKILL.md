---
name: moonctl
description: "Generate a MoonBit service project, data model, GraphQL schema, typed client or SQL migration from a `.api` spec, a `.proto` file or a SQL schema. Reach for it when the task is to scaffold a service or turn a spec into code rather than write that code by hand."
---

# moonctl

`moonbitstack/moonctl` turns a spec into code and hands it back as text: the
library never touches the disk. The `mctl` binary is the same logic plus the
reading and the writing, so a shell script wants `mctl gen …` and a build step
wants the library.

## Install

```bash
moon add moonbitstack/moonctl
```

```moonbit
import {
  "moonbitstack/moonctl",
}
```

## A spec becomes an application

```moonbit
let spec = @moonctl.parse("service greet {\n  get /ping ping\n}\n")
let code = @moonctl.generate(spec)
assert_eq(code.contains("pub fn build_app() -> @moonapi.App"), true)
```

`parse` raises a `SpecError` that names the line it could not read — a misspelt
verb, a route with no `@handler`, a field with no type. `parse_lenient` skips those
lines instead, for a spec that is still being written.

## A whole project, written where you say

`generate_tree` returns the layered project (`etc/`, `internal/config`,
`internal/svc`, `internal/handler`, `internal/logic`) as files, each marked
`Always` — moonctl owns it and rewrites it — or `Once` — it is written once and
belongs to the author. `tree_plan` is what decides which of them to write, so a
second run keeps every handler body already filled in:

```moonbit
let tree = @moonctl.generate_tree(spec)
let writes = @moonctl.tree_plan(tree, path => false)
assert_eq(writes.length() > 0, true)
```

The callback answers "is this path already on disk". Answer honestly — the
generator only ever consults it for `Once` files.

## A SQL schema becomes a model and its CRUD

```moonbit
let sql = "CREATE TABLE items (\n  id INTEGER PRIMARY KEY,\n  name TEXT NOT NULL\n);\n"
let crud = @moonctl.generate_crud_from_ddl(sql)
assert_eq(crud.contains("pub fn items_insert("), true)
```

The generated file compiles against `moonbitstack/moonorm` + `moonbitstack/moondb`,
so a consumer imports both. `CREATE INDEX` becomes the model's index list, a
`FOREIGN KEY` the column's `references`; the annotated tree (`moonbitstack/moonctl/scaffold`'s
`generate_orm_tree_from_ddl`) spells the same schema as `#orm.index`,
`#orm.has_many` and `#orm.belongs_to` instead.

## Your own template

The engine is Go's `text/template` in MoonBit: `{{.Field}}`, `{{if}}`, `{{range}}`,
`{{with}}`, pipelines, and the usual function library. The data is an explicit
`Value`, since MoonBit has no reflection to walk.

```moonbit
let line = @moonctl.render("{{.service}}: {{len .routes}} route(s)\n", @moonctl.spec_to_value(spec))
assert_eq(line, "greet: 1 route(s)\n")
```

A behaviour switch — what a missing key does, how much whitespace an action takes
— is an option on the template, and `parse_option` reads Go's spelling of it:

```moonbit
let strict = @moonctl.Template::new().options(
  @moonctl.parse_option("missingkey=error, trim=blanklines"),
)
let rendered = Ok(strict.parse("{{.nope}}").render(@moonctl.spec_to_value(spec))) catch {
  _ => Err(())
}
assert_eq(rendered is Err(_), true)
```

## What catches people out

- **Only a `get` streams.** `returns (stream T)` marks a route whose reply never
  ends in one body: an SSE handler in the `api` scaffold, a subscription in the
  `gql` one. A `post` with `stream` is refused while parsing, not quietly treated
  as one body.
- **`--style` does not rename the spec's own types.** It names the files and the
  handler/logic entry points moonctl invents; a `type` block keeps its spelling
  because a MoonBit type has to keep its capital. The SQL names are the spec's too:
  say them in the `info` block (`tableNaming`, `columnNaming`, `tablePlural`).
- **`Bytes` and `Map` fields reach GraphQL as `Base64` and `JSON`.** Neither has a
  `ToGql` impl a project may write — the trait and the type belong to other
  packages — so the `gql` schema declares the field as the text or the object the
  scalar carries, and generates `base64_of` / `bytes_of_base64` beside it. A map
  keyed by something other than a string is left out, and reported.
- **Generated projects pin their libraries.** `mctl` writes the versions it was
  built with; a project that wants a newer release edits its own `moon.mod`.
- **The binary needs `moon` on `PATH`** to format what it writes. Without it,
  generation still writes every file and says so.
