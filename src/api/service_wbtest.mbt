///|
/// The names of the service blocks in `spec`, in declaration order.
fn block_names(spec : Spec) -> Array[String] {
  let out : Array[String] = []
  for s in spec.services {
    out.push(s.name)
  }
  out
}

///|
/// The handler names of one service block.
fn block_handlers(spec : Spec, name : String) -> Array[String] {
  let out : Array[String] = []
  for s in spec.services {
    if s.name == name {
      for r in s.routes {
        out.push(r.handler)
      }
    }
  }
  out
}

///|
test "each service block keeps its own routes" {
  let spec = parse(
    (
      #|service alpha {
      #|  get /a a
      #|  get /a2 a2
      #|}
      #|
      #|service beta {
      #|  get /b b
      #|}
    ),
  )
  assert_eq(block_names(spec), ["alpha", "beta"])
  assert_eq(block_handlers(spec, "alpha"), ["a", "a2"])
  assert_eq(block_handlers(spec, "beta"), ["b"])
  // the flattened list still holds every route, in file order
  assert_eq(spec.routes.length(), 3)
  // and the module takes the name of the first block
  assert_eq(spec.service, "alpha")
}

///|
test "two blocks naming one service are that service" {
  let spec = parse(
    (
      #|@server(group: user)
      #|service greet {
      #|  get /ping ping
      #|}
      #|
      #|@server(group: admin)
      #|service greet {
      #|  delete /purge purge
      #|}
    ),
  )
  assert_eq(block_names(spec), ["greet"])
  assert_eq(block_handlers(spec, "greet"), ["ping", "purge"])
}

///|
test "a route outside any service block still belongs to the file's service" {
  let spec = parse("get /loose loose")
  assert_eq(block_names(spec), ["app"])
  assert_eq(block_handlers(spec, "app"), ["loose"])
}

///|
test "a route belongs to the block that declared it, not the previous one" {
  let spec = parse(
    (
      #|service alpha {
      #|  get /a a
      #|}
      #|
      #|service beta {
      #|  get /b b
      #|}
      #|
      #|service gamma {
      #|  get /g g
      #|}
    ),
  )
  assert_eq(block_names(spec), ["alpha", "beta", "gamma"])
  assert_eq(block_handlers(spec, "beta"), ["b"])
  assert_eq(block_handlers(spec, "gamma"), ["g"])
}

///|
test "imports merge into the service of the same name" {
  let files : Map[String, String] = Map([
    ("user.api", "service greet {\n  get /u u\n}"),
  ])
  let spec = parse_all(
    "import \"user.api\"\nservice greet {\n  get /p p\n}", files,
  )
  assert_eq(block_names(spec), ["greet"])
  assert_eq(block_handlers(spec, "greet"), ["u", "p"])
}

///|
test "a field name ending in ? is an optional field" {
  let spec = parse("type Q {\n  note?: string\n  tag: string\n}")
  assert_eq(spec.types[0].fields[0].name, "note")
  assert_eq(spec.types[0].fields[0].type_, "String?")
  assert_eq(spec.types[0].fields[0].optional(), false)
  assert_eq(spec.types[0].fields[1].name, "tag")
  assert_eq(spec.types[0].fields[1].type_, "String")
}
