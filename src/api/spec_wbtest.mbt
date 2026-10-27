///|
test "an import on one line closes on that line" {
  let spec = parse("import ( \"a.api\" \"b.api\" )\nservice greet {\n}")
  assert_eq(spec.imports, ["a.api", "b.api"])
}

///|
test "an import is a statement, not a field of a type block left open" {
  let spec = parse_lenient("type User {\n  id: int64\nimport \"a.api\"\n")
  assert_eq(spec.imports, ["a.api"])
  assert_eq(spec.types[0].fields.length(), 1)
}

///|
test "api parser: four route arities and a grouped type block" {
  let src =
    #|syntax = "v1"
    #|
    #|type (
    #|  LoginReq {
    #|    name string `json:"name"`
    #|  }
    #|  LoginResp {
    #|    token string `json:"token"`
    #|  }
    #|)
    #|
    #|service demo-api {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @handler upload
    #|  post /upload (LoginReq)
    #|
    #|  @handler list
    #|  get /list returns (LoginResp)
    #|
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|
    #|  get /legacy legacyHandler "legacy summary"
    #|}
  let spec = parse(src)
  let mut names = ""
  for t in spec.types {
    names = names + t.name + ";"
  }
  inspect(names, content="LoginReq;LoginResp;")
  let mut sig = ""
  for r in spec.routes {
    sig = sig +
      r.verb +
      " " +
      r.path +
      " h=" +
      r.handler +
      " q=" +
      r.req +
      " s=" +
      r.resp +
      "\n"
  }
  inspect(
    sig,
    content=(
      #|get /ping h=ping q= s=
      #|post /upload h=upload q=LoginReq s=
      #|get /list h=list q= s=LoginResp
      #|post /login h=login q=LoginReq s=LoginResp
      #|get /legacy h=legacyHandler q= s=
      #|
    ),
  )
}

///|
test "a multi-line @server block carries every annotation" {
  let src =
    #|@server (
    #|  group:      user
    #|  prefix:     /api/v1
    #|  jwt:        Auth
    #|  middleware: Log,Trace
    #|  maxBytes:   1048576
    #|  timeout:    3s
    #|  signature:  true
    #|  swagger:    "user.json"
    #|)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = parse(src)
  let g = spec.groups[0]
  assert_eq(g.name, "user")
  assert_eq(g.prefix, "/api/v1")
  assert_eq(g.jwt, "Auth")
  assert_eq(g.middleware, ["Log", "Trace"])
  assert_eq(g.max_bytes, 1048576L)
  assert_eq(g.timeout, "3s")
  assert_eq(g.signature, true)
  assert_eq(g.extra.length(), 1)
  assert_eq(g.extra[0].0, "swagger")
  assert_eq(g.extra[0].1, "user.json")
}

///|
test "each service block takes the @server block above it" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler login
    #|  post /login
    #|}
    #|
    #|@server(group: admin, prefix: /admin/)
    #|service greet {
    #|  @handler purge
    #|  delete /purge
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = parse(src)
  assert_eq(spec.groups.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/login")
  assert_eq(spec.routes[1].path, "/admin/purge")
  assert_eq(spec.routes[2].path, "/ping")
  match spec.routes[2].group {
    Some(g) => fail("an ungrouped route picked up group " + g.name)
    None => ()
  }
}

///|
test "a trailing comment stays out of a field type and a route summary" {
  let src =
    #|type User {
    #|  id:   int64  // the primary key
    #|  name: string `json:"name"` // display name
    #|  Note  string // the go-struct form too
    #|}
    #|
    #|service greet {
    #|  get /ping ping "health check" // liveness
    #|  get /pong pong // no summary on this one
    #|}
  let spec = parse(src)
  let user = spec.types[0]
  assert_eq(user.fields[0].type_, "Int64")
  assert_eq(user.fields[1].type_, "String")
  assert_eq(user.fields[1].tag, "json:\"name\"")
  assert_eq(user.fields[2].type_, "String")
  assert_eq(spec.routes[0].summary, "health check")
  assert_eq(spec.routes[1].handler, "pong")
  assert_eq(spec.routes[1].summary, "")
}

///|
test "@doc is read in every spelling goctl writes" {
  // the block form, over several lines
  inspect(
    parse(
      (
        #|service greet {
        #|  @doc (
        #|    summary: "log a user in"
        #|  )
        #|  @handler login
        #|  post /login
        #|}
      ),
    ).routes[0].summary,
    content="log a user in",
  )
  // the same block on one line, and `description` standing in for `summary`
  inspect(
    parse(
      "service greet {\n  @doc(summary: \"ping\")\n  @handler a\n  get /a\n}",
    ).routes[0].summary,
    content="ping",
  )
  inspect(
    parse(
      "service greet {\n  @doc(description: \"pong\")\n  @handler b\n  get /b\n}",
    ).routes[0].summary,
    content="pong",
  )
  // and the two quoted forms
  inspect(
    parse("service greet {\n  @doc \"quoted\"\n  @handler c\n  get /c\n}").routes[0].summary,
    content="quoted",
  )
  inspect(
    parse("service greet {\n  @doc(\"parens\")\n  @handler d\n  get /d\n}").routes[0].summary,
    content="parens",
  )
}

///|
test "a quoted annotation value keeps its commas" {
  let spec = parse("@server(swagger: \"a,b\", group: user)\nservice greet {\n}")
  let g = spec.groups[0]
  assert_eq(g.name, "user")
  assert_eq(g.extra[0], ("swagger", "a,b"))
}

///|
test "parse_lenient reads what it can and reports nothing" {
  let spec = parse_lenient(
    (
      #|service greet {
      #|  gett /ping ping
      #|  get /pong pong
      #|}
    ),
  )
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.routes[0].handler, "pong")
}

///|
test "parse a .api spec" {
  let src =
    #|service greet {
    #|  get /ping ping "health check"
    #|  get /users/:id get_user
    #|  post /users create_user "create a user"
    #|}
    #|
  let spec = parse(src)
  assert_eq(spec.service, "greet")
  assert_eq(spec.routes.length(), 3)
  assert_eq(spec.routes[0].verb, "get")
  assert_eq(spec.routes[0].path, "/ping")
  assert_eq(spec.routes[0].handler, "ping")
  assert_eq(spec.routes[0].summary, "health check")
  assert_eq(spec.routes[1].path, "/users/:id")
  assert_eq(spec.routes[1].summary, "")
  assert_eq(spec.routes[2].verb, "post")
}

///|
test "parse type blocks into schemas" {
  let src =
    #|type User {
    #|  id:    int64
    #|  name:  string
    #|  admin: bool
    #|  tags:  []string
    #|  meta:  map[string]int
    #|}
    #|
    #|service greet {
    #|  get /users/:id get_user
    #|}
  let spec = parse(src)
  assert_eq(spec.service, "greet")
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.types.length(), 1)
  let user = spec.types[0]
  assert_eq(user.name, "User")
  assert_eq(user.fields.length(), 5)
  assert_eq(user.fields[0].name, "id")
  assert_eq(user.fields[0].type_, "Int64")
  assert_eq(user.fields[1].type_, "String")
  assert_eq(user.fields[2].type_, "Bool")
  assert_eq(user.fields[3].type_, "Array[String]")
  assert_eq(user.fields[4].type_, "Map[String, Int32]")
}
