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
