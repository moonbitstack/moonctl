///|
/// The name of every type in `spec`, in order.
fn type_names(spec : Spec) -> Array[String] {
  let out : Array[String] = []
  for t in spec.types {
    out.push(t.name)
  }
  out
}

///|
test "a single import and a grouped one both name their files" {
  let src =
    #|import "user.api"
    #|import (
    #|  "shared/base.api"
    #|  "../common.api"
    #|)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  assert_eq(parse(src).imports, ["user.api", "shared/base.api", "../common.api"])
  assert_eq(deps(src, from="spec/greet.api"), [
    "spec/user.api", "spec/shared/base.api", "common.api",
  ])
  // an absolute import points where it says, and `.` folds away
  assert_eq(
    resolve_import("spec/greet.api", "/etc/shared/./base.api"),
    "/etc/shared/base.api",
  )
  // including one off a Windows drive, and a Windows separator on the way in
  assert_eq(
    resolve_import("spec/greet.api", "C:\\specs\\base.api"),
    "C:/specs/base.api",
  )
  assert_eq(resolve_import("spec\\greet.api", "base.api"), "spec/base.api")
}

///|
test "an import resolves against the file that wrote it" {
  let files : Map[String, String] = Map([
    ("api/base/types.api", "type Base {\n  id: int64\n}\n"),
    (
      "api/user.api", "import \"base/types.api\"\ntype User {\n  name: string\n}\n",
    ),
  ])
  let spec = parse_all(
    "import \"user.api\"\nservice greet {\n}",
    files,
    from="api/greet.api",
  )
  assert_eq(type_names(spec), ["Base", "User"])
}

///|
test "a file two others import is merged once" {
  let files : Map[String, String] = Map([
    ("base.api", "type Base {\n  id: int64\n}\n"),
    ("left.api", "import \"base.api\"\ntype Left {\n  a: int\n}\n"),
    ("right.api", "import \"base.api\"\ntype Right {\n  b: int\n}\n"),
  ])
  let main =
    #|import (
    #|  "left.api"
    #|  "right.api"
    #|)
    #|service greet {
    #|}
  assert_eq(type_names(parse_all(main, files, from="main.api")), [
    "Base", "Left", "Right",
  ])
}

///|
test "a cycle back to the importing file terminates" {
  let files : Map[String, String] = Map([
    ("base.api", "import \"main.api\"\ntype Base {\n  id: int64\n}\n"),
  ])
  let main = "import \"base.api\"\nservice greet {\n}"
  assert_eq(type_names(parse_all(main, files, from="main.api")), ["Base"])
}

///|
test "an import that is not among the files is named" {
  try
    parse_all(
      "import \"user.api\"\nservice greet {\n}",
      Map([]),
      from="spec/greet.api",
    )
    |> ignore
  catch {
    e => inspect(e, content="spec/greet.api: cannot read import \"user.api\"")
  } noraise {
    _ => fail("a missing import parsed")
  }
}

///|
test "a complaint from an imported file names that file" {
  let files : Map[String, String] = Map([
    ("user.api", "service greet {\n  gett /ping ping\n}"),
  ])
  try
    parse_all("import \"user.api\"\nservice greet {\n}", files) |> ignore
  catch {
    e => inspect(e, content="line 2: user.api: unknown verb \"gett\"")
  } noraise {
    _ => fail("a broken import parsed")
  }
}

///|
test "an import that climbs past the start keeps saying so" {
  // dropping the `..` would silently point at another file
  assert_eq(resolve_import("greet.api", "../../base.api"), "../../base.api")
  assert_eq(resolve_import("api/greet.api", "../../base.api"), "../base.api")
  assert_eq(resolve_import("a/b/greet.api", "../../base.api"), "base.api")
}

///|
test "the importing file's own service name wins" {
  let files : Map[String, String] = Map([
    ("user.api", "service account {\n  @handler ping\n  get /ping\n}"),
  ])
  let spec = parse_all(
    "import \"user.api\"\nservice greet {\n}",
    files,
    from="greet.api",
  )
  assert_eq(spec.service, "greet")
}

///|
test "a complaint about the file the caller handed in names only the line" {
  try
    parse_all(
      "service greet {\n  gett /ping ping\n}",
      Map([]),
      from="greet.api",
    )
    |> ignore
  catch {
    // the file is the one the caller already named, so repeating it would be noise
    e => inspect(e, content="line 2: unknown verb \"gett\"")
  } noraise {
    _ => fail("a broken spec parsed")
  }
}

///|
test "a service name comes from the import when the importer has none" {
  let files : Map[String, String] = Map([
    ("user.api", "service account {\n  @handler ping\n  get /ping\n}"),
  ])
  assert_eq(parse_all("import \"user.api\"", files).service, "account")
}
