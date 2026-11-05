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
async fn read_files(input : String) -> Map[String, String] {
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
  files
}

///|
async fn read_spec(input : String) -> @moonctl.Spec {
  let files = read_files(input)
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
async fn gen_api(input : String, opts : Opts) -> Unit {
  try {
    if opts.flat {
      let spec = read_spec(input)
      let out = replace_ext(input, ".api", ".mbt")
      @fs.write_file(out, @moonctl.generate(spec), create_mode=CreateOrTruncate)
      println("mctl: generated " + out + " from " + input)
      return
    }
    // A library named on the command line wins; otherwise the `home` the config
    // file carries is used, so a team sets it once. `--remote` is never taken from
    // the config: checking a repository out is a decision, not a default.
    let mut home = opts.home
    if home == "" && opts.remote == "" && @fs.exists(config_path()) {
      let cfg = read_config()
      home = cfg.home
    }
    let lib = @cli.library(home~, remote=opts.remote, branch=opts.branch)
    if @cli.is_bundled(lib) == false {
      return gen_api_through_library(input, opts, lib)
    }
    let spec = read_spec(input)
    write_tree(
      input,
      @moonctl.generate_tree(
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
/// `gen api` with a template library: check `--remote` out when that is what was
/// asked for, read the library's service template, and write what it renders. The
/// checkout is a temporary directory and is removed afterwards.
async fn gen_api_through_library(
  input : String,
  opts : Opts,
  lib : @cli.Library,
) -> Unit {
  let mut checkout = ""
  try {
    let root = if lib.home != "" {
      lib.home
    } else {
      let dir = checkout_remote(lib.remote, lib.branch) catch {
        e => return println("mctl: " + e.to_string())
      }
      checkout = dir
      dir
    }
    let entry = match @cli.find_template("api-service") {
      Some(t) => t
      None =>
        return println("mctl: the template library has no api-service entry")
    }
    let files : Array[@moonctl.TemplateFile] = []
    read_template_dir(@cli.template_dir(root, entry), files)
    if files.length() == 0 {
      println("mctl: no template files under " + @cli.template_dir(root, entry))
    } else {
      gen_api_from_library(input, root, opts.dir, files)
    }
  } catch {
    e => println("mctl: error reading the template library: " + e.to_string())
  }
  if checkout != "" {
    remove_checkout(checkout)
  }
}

///|
/// Remove a cloned template library. `git` marks the files in its object store
/// read-only on Windows, and a recursive remove refuses to delete those, so every
/// entry is made writable first.
async fn remove_checkout(dir : String) -> Unit {
  let writable = async fn(parent : String, names : Array[String]) -> Unit {
    for name in names {
      @fs.chmod(parent + "/" + name, 0o700) catch {
        _ => ()
      }
    }
  }
  @fs.walk(dir, writable, allow_failure=true) catch {
    _ => ()
  }
  @fs.chmod(dir, 0o700) catch {
    _ => ()
  }
  @fs.rmdir(dir, recursive=true) catch {
    e => println("mctl: could not remove " + dir + ": " + e.to_string())
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
  format_written(module_root(files), files)
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
/// Every file under `root`, as a template library entry: its path relative to `root`
/// and its text. Directories are descended into; a file that cannot be read as text
/// is skipped, since a template library is source.
async fn read_template_dir(
  root : String,
  out : Array[@moonctl.TemplateFile],
) -> Unit {
  let base = if @text.ends_with(root, "/") { root } else { root + "/" }
  let read = async fn(dir : String, names : Array[String]) -> Unit {
    for name in names {
      let full = dir + "/" + name
      if @fs.kind(full) is @fs.Regular {
        let text = @fs.read_file(full).text() catch { _ => continue }
        let rel = if @text.starts_with(full, base) {
          full[base.length():].to_owned()
        } else {
          name
        }
        out.push({ path: rel, text, })
      }
    }
  }
  @fs.walk(root, read)
}

///|
/// Check `remote` out at `branch` into a fresh temporary directory, and return it.
/// A shallow single-branch checkout is all a template library needs.
async fn checkout_remote(remote : String, branch : String) -> String {
  let dir = @fs.tmpdir(prefix="mctl-templates")
  let (code, _out, err) = @process.collect_output("git", [
    "clone", "--depth", "1", "--branch", branch, remote, dir,
  ])
  if code != 0 {
    abort("git clone " + remote + " failed: " + err.text())
  }
  dir
}

///|
/// Generate from a template library instead of the built-in scaffolds: render every
/// file under the library's `api/service` directory over the spec and write it under
/// `dir`. `root` is the `--home` directory, or the checkout of `--remote`.
async fn gen_api_from_library(
  input : String,
  root : String,
  dir : String,
  files : Array[@moonctl.TemplateFile],
) -> Unit {
  try {
    let spec = read_spec(input)
    let out = @moonctl.render_template_dir(spec, files)
    for entry in out {
      write_gen_file({ path: at_dir(dir, entry.0), content: entry.1, })
    }
    println(
      "mctl: wrote " +
      out.length().to_string() +
      " file(s) from " +
      input +
      " through the template library at " +
      root,
    )
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// `path` under `dir`, or `path` itself when no output directory was named.
fn at_dir(dir : String, path : String) -> String {
  if dir == "" {
    path
  } else if @text.ends_with(dir, "/") {
    dir + path
  } else {
    dir + "/" + path
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
    format_written(module_root(files), files)
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
  home : String
  remote : String
  branch : String
}

///|
/// Split a command line into its positional words and the flags mctl understands.
/// Both `--style go_zero` and `--style=go_zero` are read.
fn split_flags(argv : Array[String]) -> (Array[String], Opts) {
  let words : Array[String] = []
  let mut style = "gozero"
  let mut dir = ""
  let mut flat = false
  let mut home = ""
  let mut remote = ""
  let mut branch = @moonctl.default_branch
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "--flat" {
      flat = true
      i = i + 1
    } else if @text.starts_with(a, "--") {
      let rest = a[2:].to_owned()
      let eq = @text.index_of_str(rest, "=")
      let (name, inline) = if eq >= 0 {
        (rest[0:eq].to_owned(), Some(rest[eq + 1:].to_owned()))
      } else {
        (rest, None)
      }
      if name == "style" ||
        name == "dir" ||
        name == "home" ||
        name == "remote" ||
        name == "branch" {
        // `--flag value` and `--flag=value` both read; a value flag with nothing
        // after it keeps its default rather than swallowing the next command word.
        let from_next = inline is None && i + 1 < argv.length()
        let value = match inline {
          Some(v) => Some(v)
          None => if from_next { Some(argv[i + 1]) } else { None }
        }
        match value {
          Some(v) =>
            if name == "style" {
              style = v
            } else if name == "dir" {
              dir = v
            } else if name == "home" {
              home = v
            } else if name == "remote" {
              remote = v
            } else {
              branch = v
            }
          None => words.push(a)
        }
        i = i + (if from_next { 2 } else { 1 })
      } else {
        words.push(a)
        i = i + 1
      }
    } else {
      words.push(a)
      i = i + 1
    }
  }
  (words, { style, dir, flat, home, remote, branch, })
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
    "api" => gen_api(file, opts)
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
  if rest.length() > 0 && rest[0] == "serve" {
    return cmd_serve(tail(rest, 1))
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
