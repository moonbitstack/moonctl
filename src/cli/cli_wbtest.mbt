///|
/// Whether `hay` contains `needle`.
fn has(hay : String, needle : String) -> Bool {
  @text.index_of_str(hay, needle) >= 0
}

///|
test "the usage page names every command" {
  let page = usage_text("0.12.1")
  assert_eq(has(page, "mctl 0.12.1"), true)
  for c in commands() {
    assert_eq(has(page, c.usage), true)
  }
  // the flags the template library adds are on the page too
  assert_eq(has(page, "--home <path>"), true)
  assert_eq(has(page, "--branch <name>"), true)
}

///|
test "completion is generated from the command table" {
  let bash = completion("bash")
  assert_eq(has(bash, "complete -F _mctl mctl"), true)
  for name in command_names() {
    assert_eq(has(bash, name), true)
  }
  // sub-commands complete at the second word
  assert_eq(
    has(
      bash, "api) COMPREPLY=( $(compgen -W \"format validate doc ts dart kt java new\"",
    ),
    true,
  )
  assert_eq(has(completion("fish"), "complete -c mctl"), true)
  assert_eq(has(completion("zsh"), "compdef _mctl mctl"), true)
  assert_eq(has(completion("powershell"), "Register-ArgumentCompleter"), true)
  assert_eq(completion("tcsh"), "")
}

///|
test "a config file reads back what it wrote" {
  let text = "# kept\nhome = /opt/templates\nbranch = dev\nstyle = go_zero\ntemplate = api-native\ntemplate = flat\n"
  let c = parse_config(text)
  assert_eq(c.home, "/opt/templates")
  assert_eq(c.branch, "dev")
  assert_eq(c.style, "go_zero")
  assert_eq(c.templates.length(), 2)
  // a key the file does not set keeps its default
  assert_eq(c.remote, "https://github.com/moonbitstack/templates")
  assert_eq(config_text(c).contains("home = /opt/templates"), true)
  // and the round trip is stable
  assert_eq(parse_config(config_text(c)).templates.length(), 2)
}

///|
test "config get and set touch one key each" {
  let c = default_config()
  assert_eq(config_get(c, "branch"), Some("main"))
  assert_eq(config_get(c, "nonsense"), None)
  let c2 = config_set(c, "branch", "release")
  assert_eq(config_get(c2, "branch"), Some("release"))
  assert_eq(config_get(c2, "style"), Some("gozero"))
  // `template` appends, and does not repeat itself
  let c3 = config_set(
    config_set(c2, "template", "api-flat"),
    "template",
    "api-flat",
  )
  assert_eq(c3.templates.length(), 1)
}

///|
test "a v1 config migrates and says what it changed" {
  let v1 = "MOONCTL_HOME = /opt/mctl\nMOONCTL_STYLE = goZero\nGOCTL_REMOTE = https://example.com/t\n"
  let (text, changes) = migrate_config(v1)
  assert_eq(has(text, "version = 2"), true)
  assert_eq(has(text, "home = /opt/mctl"), true)
  assert_eq(has(text, "style = goZero"), true)
  assert_eq(has(text, "remote = https://example.com/t"), true)
  assert_eq(changes.length() > 0, true)
}

///|
test "the template library lists what it can generate" {
  assert_eq(find_template("api-service") is Some(_), true)
  assert_eq(find_template("nope") is Some(_), false)
  assert_eq(templates_of("api").length(), 5)
  let table = template_table()
  for t in templates() {
    assert_eq(has(table, "`" + t.name + "`"), true)
  }
  match find_template("model-mongo") {
    Some(t) => assert_eq(has(template_detail(t), "model/mongo"), true)
    None => panic()
  }
}

///|
test "upgrade moves the pins it was asked to move" {
  let mod =
    #|name = "example/app"
    #|
    #|import {
    #|  "moonbitlang/async@0.22.5",
    #|  "moonbitstack/moondb@0.2.0",
    #|  "moonbitstack/moonjson@0.4.0",
    #|}
  assert_eq(pinned_version(mod, "moonbitstack/moondb"), Some("0.2.0"))
  assert_eq(pinned_version(mod, "moonbitstack/nope"), None)
  let (text, changes) = upgrade_pins(
    mod,
    ["moonbitstack/moondb", "moonbitstack/nope"],
    "0.3.4",
  )
  assert_eq(has(text, "\"moonbitstack/moondb@0.3.4\""), true)
  // a module the file does not pin is reported, not added
  assert_eq(has(text, "moonbitstack/nope"), false)
  assert_eq(changes.length(), 2)
  assert_eq(has(changes[0], "0.2.0 → 0.3.4"), true)
  assert_eq(has(changes[1], "not pinned"), true)
  // the rest of the file survives
  assert_eq(has(text, "\"moonbitlang/async@0.22.5\""), true)
}

///|
test "env and bug reports carry the environment" {
  let rows = [("moon", "0.6.20"), ("targets", "wasm, native")]
  let env = env_report("0.12.1", rows)
  assert_eq(has(env, "mctl 0.12.1"), true)
  assert_eq(has(env, "0.6.20"), true)
  let report = bug_report("api format eats my comment", "0.12.1", rows)
  assert_eq(has(report, "# api format eats my comment"), true)
  assert_eq(has(report, "| mctl | 0.12.1 |"), true)
  assert_eq(has(report, "| moon | 0.6.20 |"), true)
}

///|
test "serve takes a package, its reload flags, and passes the rest to the server" {
  let plan = parse_serve([
    "src/main", "--reload", "--reload-dir", "src", "--reload-dir", "etc", "--reload-delay",
    "0.5", "--", "--port", "9000", "--reload",
  ])
  assert_eq(plan.pkg, "src/main")
  assert_true(plan.reload)
  assert_eq(plan.dirs, ["src", "etc"])
  assert_eq(plan.delay, 500)
  assert_eq(plan.args, ["--port", "9000", "--reload"])
}

///|
test "serve starts from uvicorn's defaults, without reloading" {
  let plan = parse_serve([])
  assert_eq(plan.pkg, ".")
  assert_false(plan.reload)
  assert_eq(plan.dirs, reload_dirs)
  assert_eq(plan.delay, reload_delay)
  assert_eq(plan.args, [])
}

///|
test "serve refuses what it does not understand" {
  for
    bad in [
      ["--nope"],
      ["a", "b"],
      ["--reload-delay"],
      ["--reload-delay", "soon"],
      ["--reload-delay", "0"],
      ["--reload-dir"],
    ] {
    let refused = try {
      parse_serve(bad) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "serve watches sources and manifests, and skips what the build writes" {
  for name in ["main.mbt", "pkg.generated.mbti", "moon.pkg", "moon.mod"] {
    assert_true(is_watched(name))
  }
  for name in ["README.md", "main.o", "moon.lock"] {
    assert_false(is_watched(name))
  }
  for dir in ["_build", "a/_build", "target", "./.git", ".mooncakes"] {
    assert_true(is_skipped(dir))
  }
  for dir in [".", "..", "src", "./src/main"] {
    assert_false(is_skipped(dir))
  }
}

///|
test "serve finds the executable in what moon run prints" {
  assert_eq(
    built_binary(
      "{\"artifacts_path\":[\"_build/native/debug/build/main/main.exe\"]}",
    ),
    Some("_build/native/debug/build/main/main.exe"),
  )
  assert_eq(built_binary("{\"artifacts_path\":[]}"), None)
  assert_eq(built_binary("not json"), None)
}

///|
test "the template library a run reads from is the bundled one by default" {
  let lib = library()
  assert_eq(is_bundled(lib), true)
  assert_eq(lib.branch, "main")
  // --home wins over --remote, and --branch names the branch to check out
  let local_lib = library(home="lib", remote="r.git", branch="dev")
  assert_eq(is_bundled(local_lib), false)
  assert_eq(local_lib.home, "lib")
  assert_eq(local_lib.branch, "dev")
  let remote = library(remote="r.git")
  assert_eq(is_bundled(remote), false)
  assert_eq(remote.branch, "main")
}

///|
test "a template entry is read from under the library root" {
  let t = match find_template("api-service") {
    Some(t) => t
    None => fail("api-service is in the bundled library")
  }
  inspect(template_dir("", t), content="api/service")
  inspect(template_dir("lib/", t), content="lib/api/service")
  inspect(template_dir("lib", t), content="lib/api/service")
}

///|
test "the starter library is a template home mctl can read back" {
  let pins : Map[String, String] = Map([
    ("moonbitstack/moonapi", "1.2.3"),
    ("moonbitstack/moonasgi", "4.5.6"),
    ("moonbitstack/mooncat", "7.8.9"),
  ])
  let files = template_starter(pins)
  let mut main = ""
  let mut mod = ""
  let mut pkg = ""
  for f in files {
    if f.0 == "api/service/{{.service}}.mbt" {
      main = f.1
    }
    if f.0 == "api/service/moon.mod" {
      mod = f.1
    }
    if f.0 == "api/service/moon.pkg" {
      pkg = f.1
    }
  }
  // every entry sits under the path the api-service catalogue entry names
  for f in files {
    assert_eq(has(f.0, "api/service/"), true)
  }
  assert_eq(main != "", true)
  assert_eq(has(main, "app.{{.verb}}(\"{{.route}}\""), true)
  // the release is pinned in moon.mod and only named in moon.pkg
  assert_eq(has(mod, "\"moonbitstack/moonapi@1.2.3\""), true)
  assert_eq(has(pkg, "\"moonbitstack/moonapi\","), true)
  assert_eq(has(pkg, "@1.2.3"), false)
}

///|
test "every kind exports a spec that parses" {
  let kinds = export_kinds()
  assert_eq(kinds.length(), 7)
  for kind in kinds {
    match export_sample(kind) {
      Some(files) => {
        assert_eq(files.length() > 0, true)
        for entry in files {
          // the file is named for the kind, so two exports in one directory fit
          assert_eq(@text.starts_with(entry.0, kind + "-sample."), true)
          // it ends with a newline, so it reads as a file and not as a paste
          assert_eq(@text.ends_with(entry.1, "\n"), true)
        }
      }
      None => abort("no spec exported for " + kind)
    }
  }
  // an unknown kind is refused rather than guessed
  assert_eq(export_sample("nope") is None, true)
}

///|
test "the api and gql samples are specs the parser reads" {
  let spec = (kind : String) => {
    let files = match export_sample(kind) {
      Some(f) => f
      None => abort("no spec exported for " + kind)
    }
    @api.parse(files[0].1)
  }
  let api = spec("api")
  assert_eq(api.service, "greet")
  assert_eq(api.routes.length(), 2)
  assert_eq(api.types.length(), 2)
  // the gql sample carries a streaming route, which is a subscription there
  let gql = spec("gql")
  assert_eq(gql.routes.length(), 2)
  assert_eq(gql.routes[1].stream, true)
  // and the model sample asks for plural tables
  let model = spec("model")
  assert_eq(
    model.info.any(kv => kv.0 == "tableNaming" && kv.1 == "plural_snake"),
    true,
  )
}
