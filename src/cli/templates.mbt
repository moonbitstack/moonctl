// `mctl template` — the bundled template library, described.
//
// A template is a directory of files with `{{.Name}}` holes in them, plus the rules
// mctl needs to fill them: which spec each kind reads, what it writes, and what a
// user has to rename. The catalogue lives here so `mctl template list` and `mctl
// template show` describe the same thing the generators use, and so a remote
// library (--remote, --branch) can be compared entry by entry.

///|
/// One template: the name a user types, the kind of spec it reads, one sentence on
/// what it produces, and the directory under the template home it lives in.
pub(all) struct TemplateEntry {
  name : String
  kind : String
  description : String
  path : String
}

///|
/// The bundled library, in the order it is listed.
pub fn templates() -> Array[TemplateEntry] {
  [
    {
      name: "api-service",
      kind: "api",
      description: "a moonapi service: routes, handlers, logic, config and a Dockerfile",
      path: "api/service",
    },
    {
      name: "api-flat",
      kind: "api",
      description: "the same routes and types in one .mbt file, for a small service",
      path: "api/flat",
    },
    {
      name: "rpc-service",
      kind: "proto",
      description: "a moonrpc service: messages, codecs, handler table and a client",
      path: "rpc/service",
    },
    {
      name: "gql-service",
      kind: "api",
      description: "a moongql schema and resolver over the spec's types",
      path: "gql/service",
    },
    {
      name: "mcp-server",
      kind: "api",
      description: "an MCP server whose tools are the spec's annotated handlers",
      path: "mcp/server",
    },
    {
      name: "model-mysql",
      kind: "ddl",
      description: "moonorm models and CRUD for a MySQL schema, reflected or from DDL",
      path: "model/mysql",
    },
    {
      name: "model-postgres",
      kind: "ddl",
      description: "moonorm models and CRUD for a PostgreSQL schema",
      path: "model/postgres",
    },
    {
      name: "model-mongo",
      kind: "api",
      description: "document models over a Mongo collection, with a typed collection port",
      path: "model/mongo",
    },
    {
      name: "gateway",
      kind: "proto",
      description: "an HTTP gateway that routes to a moonrpc client",
      path: "gateway/http",
    },
  ]
}

///|
/// The template called `name`, or `None`.
pub fn find_template(name : String) -> TemplateEntry? {
  for t in templates() {
    if t.name == name {
      return Some(t)
    }
  }
  None
}

///|
/// The templates of one kind — the ones a `gen` of that kind may pick.
pub fn templates_of(kind : String) -> Array[TemplateEntry] {
  let out : Array[TemplateEntry] = []
  for t in templates() {
    if t.kind == kind {
      out.push(t)
    }
  }
  out
}

///|
/// `mctl template list`: a table a reader scans rather than a paragraph they read.
pub fn template_table() -> String {
  let out : Array[String] = []
  out.push("| Template | Spec | What it produces |")
  out.push("| --- | --- | --- |")
  for t in templates() {
    out.push("| `" + t.name + "` | " + t.kind + " | " + t.description + " |")
  }
  @text.join_lines(out)
}

///|
/// `mctl template show <name>`: one entry, and where it sits in the library.
pub fn template_detail(t : TemplateEntry) -> String {
  let out : Array[String] = []
  out.push("# " + t.name)
  out.push("")
  out.push(t.description + ".")
  out.push("")
  out.push("- reads: `." + t.kind + "`")
  out.push("- lives in: `" + t.path + "` under the template home")
  out.push("- override: put your own `" + t.path + "` under `--home <dir>`")
  @text.join_lines(out)
}
