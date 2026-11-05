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
/// The template library a run reads from. Empty `home` and `remote` mean the
/// bundled library — the scaffolds in code; `--home` names a directory laid out
/// like it, `--remote` a git repository to check out at `branch`.
pub(all) struct Library {
  home : String
  remote : String
  branch : String
}

///|
/// The branch `--remote` reads when `--branch` names none.
pub let default_branch : String = "main"

///|
/// The library the three flags describe. `--home` wins over `--remote` when both are
/// given: a local directory is already checked out.
pub fn library(home? : String, remote? : String, branch? : String) -> Library {
  {
    home: home.unwrap_or(""),
    remote: remote.unwrap_or(""),
    branch: match branch {
      Some(b) if b != "" => b
      _ => default_branch
    },
  }
}

///|
/// Whether this is the bundled library, which is code rather than files.
pub fn is_bundled(lib : Library) -> Bool {
  lib.home == "" && lib.remote == ""
}

///|
/// The directory `t` is read from, given the root the library resolves to. The root
/// is the `--home` directory, or where `--remote` was checked out.
pub fn template_dir(root : String, t : TemplateEntry) -> String {
  if root == "" {
    t.path
  } else if @text.ends_with(root, "/") {
    root + t.path
  } else {
    root + "/" + t.path
  }
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

///|
/// The files `mctl template init` writes: one entry under `api/service`, small
/// enough to read in a minute and complete enough to serve the spec it is given.
/// Both the file names and the text are templates, so a library is edited as
/// templates and read back the same way.
pub fn template_starter(pins : Map[String, String]) -> Array[(String, String)] {
  let deps = [
    "moonbitstack/moonapi", "moonbitstack/moonasgi", "moonbitstack/mooncat",
  ]
  let mut pinned = "import {\n"
  let mut plain = "import {\n"
  for dep in deps {
    let version = match pins.get(dep) {
      Some(v) => "@" + v
      None => ""
    }
    pinned = pinned + "  \"" + dep + version + "\",\n"
    plain = plain + "  \"" + dep + "\",\n"
  }
  pinned = pinned + "}\n"
  plain = plain + "}\n"
  // `moon.mod` names the release, `moon.pkg` only the package.
  let mod = "name = \"{{.service}}\"\n\nversion = \"0.1.0\"\n\n" + pinned
  let pkg = plain +
    "\nsupported_targets = \"native\"\n\npkgtype(kind: \"executable\")\n"
  let main_src = "///|\n/// The {{.service}} service: one handler per route, and a server on 12000.\n" +
    "{{range .routes}}pub fn {{.handler}}(_ctx : @moonapi.Context) -> @moonasgi.Response {\n  @moonapi.text(200, \"{{.handler}}\")\n}\n\n{{end}}" +
    "///|\nfn build_app() -> @moonapi.App {\n  let app = @moonapi.App::new()\n{{range .routes}}  app.{{.verb}}(\"{{.route}}\", ctx => {{.handler}}(ctx))\n{{end}}  app\n}\n\n///|\nasync fn main {\n  let app = build_app()\n  @mooncat.serve(app, port=12000)\n}\n"
  let readme = "# {{.service}} templates\n\n`moon.mod`, `moon.pkg` and `{{.service}}.mbt`, written by `mctl template init`.\nEvery file is a template over the parsed spec: the service name, a loop over its\nroutes, and each route's verb, path, handler, summary, request type and reply type.\nGenerate with://n//n```bash\nmctl gen api <file.api> --home <this directory> --dir <output>\n```\n"
  [
    ("api/service/moon.mod", mod),
    ("api/service/moon.pkg", pkg),
    ("api/service/{{.service}}.mbt", main_src),
    ("api/service/README.md", readme),
  ]
}
