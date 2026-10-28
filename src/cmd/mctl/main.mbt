///|
/// Replace a known input extension with `suffix`; if the extension is absent the
/// suffix is simply appended. E.g. `("greet.api", ".mbt")` → `greet.mbt`,
/// `("greet.proto", "_grpc.mbt")` → `greet_grpc.mbt`.
fn replace_ext(input : String, ext : String, suffix : String) -> String {
  let n = input.length()
  let e = ext.length()
  if n >= e && input[n - e:].to_owned() == ext {
    input[0:n - e].to_owned() + suffix
  } else {
    input + suffix
  }
}

///|
/// Read `input` and every `.api` it imports — following each file's own imports in
/// turn — and parse the lot into one spec.
async fn read_spec(input : String) -> @moonctl.Spec {
  let files : Map[String, String] = Map([])
  let pending = [input]
  let mut i = 0
  while i < pending.length() {
    let path = pending[i]
    i = i + 1
    if files.contains(path) {
      continue
    }
    let source = @fs.read_file(path).text()
    files[path] = source
    for dep in @moonctl.deps(source, from=path) {
      // an import that is not there is left out of the set, so the parser reports it
      // against the file that asked for it rather than an open() failure that names
      // only the path
      if @fs.exists(dep) {
        pending.push(dep)
      }
    }
  }
  let source = match files.get(input) {
    Some(s) => s
    None => ""
  }
  @moonctl.parse_all(source, files, from=input)
}

///|
/// Read a `.api` spec and write the layered project tree — `etc/`, `internal/config`,
/// `internal/svc`, `internal/types`, `internal/handler`, `internal/logic`,
/// `internal/middleware` and the service entry point — under `dir`, naming everything
/// in `style`. A file that is already there is left as it is, except the routes and
/// the types, which follow the spec and are rewritten every run. `flat` instead
/// writes the whole scaffold to a single `<stem>.mbt`, as earlier versions did.
/// All IO failures are caught and reported so `main` never propagates an error.
async fn gen_api(
  input : String,
  style : String,
  dir : String,
  flat : Bool,
) -> Unit {
  try {
    let spec = read_spec(input)
    if flat {
      let out = replace_ext(input, ".api", ".mbt")
      @fs.write_file(out, @moonctl.generate(spec), create_mode=CreateOrTruncate)
      println("mctl: generated " + out + " from " + input)
      return
    }
    write_tree(
      input,
      @moonctl.generate_tree(spec, style=@moonctl.Style::parse(style), dir~),
    )
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Write the files of `tree` a run should touch: what moonctl owns always, what
/// it only seeds when it is not on disk yet.
async fn write_tree(input : String, tree : Array[@moonctl.TreeFile]) -> Unit {
  let here : Map[String, Bool] = Map([])
  for f in tree {
    if @fs.exists(f.path) {
      here[f.path] = true
    }
  }
  let files = @moonctl.tree_plan(tree, p => here.contains(p))
  for f in files {
    write_gen_file(f)
  }
  let kept = tree.length() - files.length()
  println(
    "mctl: wrote " +
    files.length().to_string() +
    " file(s) from " +
    input +
    (if kept == 0 {
      ""
    } else {
      "; kept the " + kept.to_string() + " already there"
    }),
  )
}

///|
/// Read a `.proto` file and write the moonrpc service tree for it, or with `flat`
/// only the messages, codecs and handler tables to `<stem>_grpc.mbt`.
async fn gen_rpc(input : String, opts : Opts) -> Unit {
  try {
    let proto = @moonctl.parse_proto(@fs.read_file(input).text())
    if opts.flat {
      let out = replace_ext(input, ".proto", "_grpc.mbt")
      @fs.write_file(
        out,
        @moonctl.generate_grpc(proto),
        create_mode=CreateOrTruncate,
      )
      println("mctl: generated " + out + " from " + input)
      return
    }
    write_tree(
      input,
      @moonctl.generate_rpc_tree(
        proto,
        style=@moonctl.Style::parse(opts.style),
        dir=opts.dir,
      ),
    )
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a `.api` spec, parse its `type` blocks, and write moonorm models +
/// `@moonorm.Table` descriptors to `<stem>_model.mbt`.
async fn gen_model(input : String) -> Unit {
  let out = replace_ext(input, ".api", "_model.mbt")
  try {
    let code = @moonctl.generate_model(read_spec(input))
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a `.api` spec, parse its `type` blocks, and write a moongql code-first
/// schema + resolver stubs to `<stem>_schema.mbt`.
async fn gen_gql(input : String, opts : Opts) -> Unit {
  try {
    let spec = read_spec(input)
    if opts.flat {
      let out = replace_ext(input, ".api", "_schema.mbt")
      @fs.write_file(
        out,
        @moonctl.generate_gql(spec),
        create_mode=CreateOrTruncate,
      )
      println("mctl: generated " + out + " from " + input)
      return
    }
    write_tree(
      input,
      @moonctl.generate_gql_tree(
        spec,
        style=@moonctl.Style::parse(opts.style),
        dir=opts.dir,
      ),
    )
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a `.api` spec, and write a moonkoog agent scaffold (one `Tool` per service
/// operation plus a `build_agent` assembly) to `<stem>_agent.mbt`.
async fn gen_agent(input : String) -> Unit {
  let out = replace_ext(input, ".api", "_agent.mbt")
  try {
    let code = @moonctl.generate_agent(read_spec(input))
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a SQL DDL file, parse its `CREATE TABLE` statements, and write a moonorm
/// data-access layer (models + typed CRUD) to `<stem>_model.mbt`.
async fn gen_crud(input : String) -> Unit {
  let out = replace_ext(input, ".sql", "_model.mbt")
  try {
    let source = @fs.read_file(input).text()
    let code = @moonctl.generate_crud_from_ddl(source)
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Index of the last `ch` in `s`, or `-1` if absent.
fn last_index_of(s : String, ch : UInt16) -> Int32 {
  let mut idx = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ch {
      idx = i
    }
  }
  idx
}

///|
/// Write one plugin-produced file, creating its parent directory when the path is
/// nested.
async fn write_gen_file(f : @moonctl.GenFile) -> Unit {
  let slash = last_index_of(f.path, '/')
  if slash > 0 {
    let dir = f.path[0:slash].to_owned()
    // `mkdir(recursive=true)` still raises if the leaf already exists, and a scaffold
    // writes several files into the same directory — so create it only once.
    if !@fs.exists(dir) {
      @fs.mkdir(dir, recursive=true)
    }
  }
  @fs.write_file(f.path, f.content, create_mode=CreateOrTruncate)
  println("mctl: wrote " + f.path)
}

///|
/// What a plugin run hands over: the program to spawn, its argv, and the JSON it
/// reads on stdin. Split out of `run_plugin` so what the binary sends can be
/// checked without spawning anything.
fn plugin_call(
  plugin : String,
  spec : @moonctl.Spec,
  input : String,
  opts : Opts,
) -> (String, Array[String], String) {
  let (bin, argv) = @moonctl.plugin_argv(plugin)
  let req = @moonctl.plugin_request(
    spec,
    api_file_path=input,
    style=opts.style,
    dir=opts.dir,
  )
  (bin, argv, req)
}

///|
/// Run an external plugin over a `.api` spec: parse the spec, hand it to the plugin
/// as goctl's `{Api, ApiFilePath, Style, Dir}` JSON on stdin, and write back the
/// `{path, content}` files the plugin prints as JSON on stdout. This is goctl's `api
/// plugin` — an out-of-tree generator driven off the same parsed spec mctl's
/// built-in generators use. `plugin` is the invocation, so a plugin that takes
/// arguments is named the way goctl names one: `"myplugin -flag value"`.
async fn run_plugin(plugin : String, input : String, opts : Opts) -> Unit {
  let req_path = input + ".mctlreq.json"
  try {
    let (bin, argv, req) = plugin_call(plugin, read_spec(input), input, opts)
    @fs.write_file(req_path, req, create_mode=CreateOrTruncate)
    let stdin = @process.redirect_from_file(req_path)
    let (code, out, err) = @process.collect_output(bin, argv, stdin~)
    @fs.remove(req_path)
    if code != 0 {
      println(
        "mctl: plugin " +
        plugin +
        " exited with code " +
        code.to_string() +
        ": " +
        err.text(),
      )
      return
    }
    let (files, refused) = @moonctl.plugin_plan(
      @moonctl.parse_gen_files(out.json()),
    )
    for note in refused {
      println("mctl: " + note)
    }
    for f in files {
      write_gen_file(f)
    }
    println(
      "mctl: plugin " +
      plugin +
      " produced " +
      files.length().to_string() +
      " file(s)" +
      (if refused.length() == 0 {
        ""
      } else {
        ", " + refused.length().to_string() + " refused"
      }),
    )
  } catch {
    e => println("mctl: plugin error: " + e.to_string())
  }
}

///|
/// Read a `.api` spec and write an OpenAPI 3.1 document (`<stem>_openapi.json`) plus
/// a Swagger UI page (`<stem>_swagger.html`) that renders it.
async fn gen_doc(input : String) -> Unit {
  let spec_out = replace_ext(input, ".api", "_openapi.json")
  let ui_out = replace_ext(input, ".api", "_swagger.html")
  try {
    let doc = @moonctl.generate_doc(read_spec(input))
    @fs.write_file(spec_out, doc, create_mode=CreateOrTruncate)
    @fs.write_file(
      ui_out,
      @moonctl.swagger_ui_stub(spec_url=spec_out),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + spec_out + " and " + ui_out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Reflect a live database's schema and write generated moonorm models + CRUD to
/// `out`. `dsn` selects the backend: `sqlite:…` reads the schema synchronously through
/// the FFI driver, `postgres://…` over the async wire protocol. This is goctl's `model
/// … datasource`.
async fn gen_datasource(dsn : String, out : String) -> Unit {
  try {
    let code = match @moonctl.parse_dsn(dsn) {
      Sqlite(path) => {
        let db = @sqlite.SqliteDriver::open(path)
        @moonctl.generate_crud_from_reflection(@reflect.reflect_sqlite(db))
      }
      Postgres(t) => {
        let conn = @pg.PgConn::connect(
          t.host,
          t.port,
          t.user,
          t.password,
          t.database,
        )
        let cols = @reflect.reflect_postgres(conn)
        conn.close()
        @moonctl.generate_crud_from_reflection(cols)
      }
    }
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from datasource " + dsn)
  } catch {
    e => println("mctl: datasource error: " + e.to_string())
  }
}

///|
/// Write a scaffolded project's files, creating nested directories as needed, and
/// report the tree that was written.
async fn write_scaffold(
  label : String,
  files : Array[@moonctl.GenFile],
) -> Unit {
  try {
    for f in files {
      write_gen_file(f)
    }
    println(
      "mctl: scaffolded " +
      label +
      " (" +
      files.length().to_string() +
      " file(s))",
    )
  } catch {
    e => println("mctl: scaffold error: " + e.to_string())
  }
}

///|
fn usage() -> Unit {
  println(@moonctl.usage_text(MCTL_VERSION))
}

///|
/// `args` without its first `n` words — the arguments of a sub-command.
fn tail(args : Array[String], n : Int32) -> Array[String] {
  let out : Array[String] = []
  for i = n; i < args.length(); i = i + 1 {
    out.push(args[i])
  }
  out
}

///|
/// The flags a command line carried, apart from its words.
struct Opts {
  style : String
  dir : String
  flat : Bool
}

///|
/// `s` with `prefix` cut off, or `None` when it does not start with one.
fn after_prefix(s : String, prefix : String) -> String? {
  if s.length() < prefix.length() {
    return None
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return None
    }
  }
  Some(s[prefix.length():].to_owned())
}

///|
/// Split a command line into its positional words and the flags mctl understands.
/// Both `--style go_zero` and `--style=go_zero` are read.
fn split_flags(argv : Array[String]) -> (Array[String], Opts) {
  let words : Array[String] = []
  let mut style = "gozero"
  let mut dir = ""
  let mut flat = false
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "--flat" {
      flat = true
    } else if a == "--style" && i + 1 < argv.length() {
      style = argv[i + 1]
      i = i + 1
    } else if a == "--dir" && i + 1 < argv.length() {
      dir = argv[i + 1]
      i = i + 1
    } else {
      match after_prefix(a, "--style=") {
        Some(v) => style = v
        None =>
          match after_prefix(a, "--dir=") {
            Some(v) => dir = v
            None => words.push(a)
          }
      }
    }
    i = i + 1
  }
  (words, { style, dir, flat, })
}

///|
/// `argv` without the `--write` / `-w` flag, and whether it carried one. Only
/// `mctl api format --write` reads it, so it is taken out before the command line is
/// split into words and the flags every generator shares.
fn take_write_flag(argv : Array[String]) -> (Array[String], Bool) {
  let out : Array[String] = []
  let mut write = false
  for a in argv {
    if a == "--write" || a == "-w" {
      write = true
    } else {
      out.push(a)
    }
  }
  (out, write)
}

///|
/// Dispatch a `gen <what> <file>` sub-command. `rpc` and `proto` are synonyms
/// (proto → moonrpc), so both spellings work.
async fn dispatch(what : String, file : String, opts : Opts) -> Unit {
  match what {
    "api" => gen_api(file, opts.style, opts.dir, opts.flat)
    "proto" | "rpc" => gen_rpc(file, opts)
    "model" => gen_model(file)
    "mongo" => model_mongo(file)
    "cache" => model_cache(file)
    "gateway" => gateway(file)
    "crud" => gen_crud(file)
    "doc" => gen_doc(file)
    "gql" => gen_gql(file, opts)
    "agent" => gen_agent(file)
    "datasource" => gen_datasource(file, "datasource_model.mbt")
    _ => usage()
  }
}

///|
/// Entry point for the `mctl` binary. `@env.args()[0]` is the executable path on
/// native, so the sub-command starts at index 1. Commands: `gen <what> <file>` (and
/// its `generate` synonym), `model datasource <dsn>`, the `api|rpc|gql|mcp|model new <name>`
/// project scaffolds, `docker`/`kube <name>`, and `plugin <exe> <file>`.
async fn main {
  let argv = @env.args()
  let rest : Array[String] = []
  for i = 1; i < argv.length(); i = i + 1 {
    rest.push(argv[i])
  }
  let (rest, write) = take_write_flag(rest)
  let (args, opts) = split_flags(rest)
  let n = args.length()
  if n >= 3 && (args[0] == "gen" || args[0] == "generate") {
    dispatch(args[1], args[2], opts)
  } else if n >= 3 && args[0] == "model" && args[1] == "datasource" {
    gen_datasource(args[2], "datasource_model.mbt")
  } else if n == 0 || args[0] == "help" {
    usage()
  } else if args[0] == "completion" {
    cmd_completion(if n >= 2 { args[1] } else { "" })
  } else if args[0] == "template" {
    cmd_template(tail(args, 1))
  } else if args[0] == "config" {
    cmd_config(tail(args, 1))
  } else if args[0] == "env" {
    cmd_env()
  } else if args[0] == "bug" {
    cmd_bug(if n >= 2 { args[1] } else { "" })
  } else if args[0] == "upgrade" {
    cmd_upgrade(if n >= 2 { args[1] } else { MCTL_VERSION })
  } else if n >= 2 && args[0] == "migrate" {
    cmd_migrate(args[1])
  } else if n >= 2 && args[0] == "quickstart" {
    cmd_quickstart(args[1])
  } else if n >= 4 &&
    args[0] == "model" &&
    args[1] == "mysql" &&
    args[2] == "datasource" {
    gen_datasource_for("mysql", args[3])
  } else if n >= 4 &&
    args[0] == "model" &&
    args[1] == "pg" &&
    args[2] == "datasource" {
    gen_datasource_for("pg", args[3])
  } else if n >= 3 && args[0] == "model" && args[1] == "mongo" {
    model_mongo(args[2])
  } else if n >= 3 && args[0] == "model" && args[1] == "cache" {
    model_cache(args[2])
  } else if n >= 2 && args[0] == "gateway" {
    gateway(args[1])
  } else if n >= 3 && args[0] == "api" && args[1] == "format" {
    api_format(args[2], write)
  } else if n >= 3 && args[0] == "api" && args[1] == "validate" {
    api_validate(args[2])
  } else if n >= 3 && args[0] == "api" && args[1] == "doc" {
    api_doc(args[2])
  } else if n >= 3 && args[0] == "api" && args[1] == "ts" {
    api_client(args[2], @moonctl.Lang::TypeScript)
  } else if n >= 3 && args[0] == "api" && args[1] == "dart" {
    api_client(args[2], @moonctl.Lang::Dart)
  } else if n >= 3 && args[0] == "api" && args[1] == "kt" {
    api_client(args[2], @moonctl.Lang::Kotlin)
  } else if n >= 3 && args[0] == "api" && args[1] == "java" {
    api_client(args[2], @moonctl.Lang::Java)
  } else if n >= 3 && args[0] == "api" && args[1] == "new" {
    write_scaffold("api project " + args[2], @moonctl.scaffold_api(args[2]))
  } else if n >= 3 && args[0] == "rpc" && args[1] == "new" {
    write_scaffold("rpc project " + args[2], @moonctl.scaffold_rpc(args[2]))
  } else if n >= 3 && args[0] == "gql" && args[1] == "new" {
    write_scaffold("gql project " + args[2], @moonctl.scaffold_gql(args[2]))
  } else if n >= 3 && args[0] == "mcp" && args[1] == "new" {
    write_scaffold("mcp project " + args[2], @moonctl.scaffold_mcp(args[2]))
  } else if n >= 3 && args[0] == "model" && args[1] == "new" {
    write_scaffold("model project " + args[2], @moonctl.scaffold_model(args[2]))
  } else if n >= 2 && args[0] == "docker" {
    write_scaffold("docker files", @moonctl.scaffold_docker(args[1]))
  } else if n >= 2 && args[0] == "kube" {
    write_scaffold("kube manifests", @moonctl.scaffold_kube(args[1]))
  } else if n >= 3 && args[0] == "plugin" {
    run_plugin(args[1], args[2], opts)
  } else {
    usage()
  }
}
