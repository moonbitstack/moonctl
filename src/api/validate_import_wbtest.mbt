///|
test "a type from an imported file is not unknown" {
  let base = "type Base {\n  Id int64 `json:\"id\"`\n}\n"
  let main = "import \"base.api\"\n\nservice shop {\n  @handler GetUser\n  get /users/:id returns (User)\n}\n\ntype User {\n  Base\n  Name string `json:\"name\"`\n}\n"
  let files : Map[String, String] = Map([])
  files["base.api"] = base
  files["main.api"] = main
  let found = validate_files(main, files, from="main.api")
  // `Base` is declared in a file the spec imports, so embedding it is not a mistake
  for d in found {
    assert_eq(d.rule == "unknown-type", false)
  }
  assert_eq(has_errors(found), false)
}

///|
test "a type nothing declares is still an error when files are given" {
  let main = "service shop {\n  @handler GetUser\n  get /users/:id returns (User)\n}\n"
  let files : Map[String, String] = Map([])
  files["main.api"] = main
  let found = validate_files(main, files, from="main.api")
  assert_eq(has_errors(found), true)
}

///|
test "a spec that will not parse is one syntax finding, not a raise" {
  let src = "service shop {\n  get /users/:id returns (User)\n}\n"
  let files : Map[String, String] = Map([])
  files["main.api"] = src
  let found = validate_files(src, files, from="main.api")
  assert_eq(found.length(), 1)
  assert_eq(found[0].rule, "syntax")
}
