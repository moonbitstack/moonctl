///|
/// A spec exercised by the plugin (de)serialisation round-trips.
let plugin_spec_src : String =
  #|service greet {
  #|  get  /ping       ping        "health check"
  #|  post /users      create_user "create a user"
  #|}
  #|
  #|type User {
  #|  id:   int64
  #|  name: string
  #|}

///|
test "spec_to_json then spec_from_json round-trips the spec" {
  let spec = parse(plugin_spec_src)
  let back = spec_from_json(spec_to_json(spec))
  assert_eq(back.service, "greet")
  assert_eq(back.routes.length(), 2)
  assert_eq(back.routes[0].verb, "get")
  assert_eq(back.routes[0].path, "/ping")
  assert_eq(back.routes[0].handler, "ping")
  assert_eq(back.routes[0].summary, "health check")
  assert_eq(back.routes[1].handler, "create_user")
  assert_eq(back.types.length(), 1)
  assert_eq(back.types[0].name, "User")
  assert_eq(back.types[0].fields.length(), 2)
  assert_eq(back.types[0].fields[0].name, "id")
  // the mapped MoonBit type survives the trip
  assert_eq(back.types[0].fields[0].type_, "Int64")
  assert_eq(back.types[0].fields[1].type_, "String")
}

///|
test "plugin_request emits the type_ member as `type`" {
  let req = plugin_request(parse(plugin_spec_src))
  assert_eq(contains(req, "\"service\": \"greet\""), true)
  assert_eq(contains(req, "\"handler\": \"ping\""), true)
  // fields carry `type`, not `type_`
  assert_eq(contains(req, "\"type\": \"Int64\""), true)
  assert_eq(contains(req, "type_"), false)
}

///|
test "the request carries goctl's four keys" {
  let req = plugin_request(
    parse(plugin_spec_src),
    api_file_path="spec/greet.api",
    style="go_zero",
    dir="out",
  )
  assert_eq(contains(req, "\"Api\": {"), true)
  assert_eq(contains(req, "\"ApiFilePath\": \"spec/greet.api\""), true)
  assert_eq(contains(req, "\"Style\": \"go_zero\""), true)
  assert_eq(contains(req, "\"Dir\": \"out\""), true)
  // and a plugin reads all four back
  let back = plugin_from_json(@json.loads(req))
  assert_eq(back.api.service, "greet")
  assert_eq(back.api.routes.length(), 2)
  assert_eq(back.api_file_path, "spec/greet.api")
  assert_eq(back.style, "go_zero")
  assert_eq(back.dir, "out")
}

///|
test "a request that names no style is read as the default one" {
  let req = plugin_request(parse(plugin_spec_src))
  // the request itself names the default, so a plugin reading the raw JSON sees one
  assert_eq(contains(req, "\"Style\": \"gozero\""), true)
  let back = plugin_from_json(@json.loads(req))
  assert_eq(back.style, "gozero")
  assert_eq(back.api_file_path, "")
  assert_eq(back.dir, "")
  // a hand-written request that names no style at all still names one a plugin can
  // spell its output with
  assert_eq(
    plugin_from_json(spec_to_json(parse(plugin_spec_src))).style,
    "gozero",
  )
  // a plugin that wants nothing but the spec need not unwrap the envelope
  let spec = spec_from_json(@json.loads(plugin_request(parse(plugin_spec_src))))
  assert_eq(spec.service, "greet")
  assert_eq(spec.routes[0].handler, "ping")
  // and a bare spec still reads as one
  assert_eq(
    spec_from_json(spec_to_json(parse(plugin_spec_src))).service,
    "greet",
  )
}

///|
test "a plugin invocation splits into the program and its argv" {
  let (bin, args) = plugin_argv("mctl-plugin --out docs -v")
  assert_eq(bin, "mctl-plugin")
  assert_eq(args, ["--out", "docs", "-v"])
  // a plugin taking no arguments is run with none
  let (alone, none_) = plugin_argv("plugin.exe")
  assert_eq(alone, "plugin.exe")
  assert_eq(none_, [])
  // a quoted word keeps its spaces, on either side
  let (quoted, qargs) = plugin_argv(
    "\"C:/Program Files/p.exe\" --dir \"my out\"",
  )
  assert_eq(quoted, "C:/Program Files/p.exe")
  assert_eq(qargs, ["--dir", "my out"])
  assert_eq(plugin_argv("").0, "")
}

///|
test "an embedded block reaches the plugin" {
  let spec = parse("type Base {\n  id: int64\n}\ntype User {\n  Base\n}")
  let back = spec_from_json(spec_to_json(spec))
  assert_eq(back.types[1].name, "User")
  assert_eq(back.types[1].embeds, ["Base"])
}

///|
test "parse_gen_files accepts the {files:[...]} envelope" {
  let j = @json.loads(
    (
      #|{"files": [
      #|  {"path": "a.mbt", "content": "let a = 1"},
      #|  {"path": "b.mbt", "content": "let b = 2"}
      #|]}
    ),
  )
  let files = parse_gen_files(j)
  assert_eq(files.length(), 2)
  assert_eq(files[0].path, "a.mbt")
  assert_eq(files[0].content, "let a = 1")
  assert_eq(files[1].path, "b.mbt")
}

///|
test "parse_gen_files accepts a bare array and skips path-less entries" {
  let j = @json.loads(
    (
      #|[
      #|  {"path": "x.txt", "content": "hi"},
      #|  {"content": "no path here"}
      #|]
    ),
  )
  let files = parse_gen_files(j)
  assert_eq(files.length(), 1)
  assert_eq(files[0].path, "x.txt")
  assert_eq(files[0].content, "hi")
}

///|
test "gen_files_to_json then parse_gen_files round-trips the files" {
  let files : Array[GenFile] = [
    { path: "routes.md", content: "# routes\n- GET /ping", },
    { path: "count.txt", content: "2", },
  ]
  let back = parse_gen_files(gen_files_to_json(files))
  assert_eq(back.length(), 2)
  assert_eq(back[0].path, "routes.md")
  assert_eq(back[0].content, "# routes\n- GET /ping")
  assert_eq(back[1].content, "2")
}
