///|
/// The name of every type in `spec`, in order.
fn type_names(spec : @api.Spec) -> Array[String] {
  let out : Array[String] = []
  for t in spec.types {
    out.push(t.name)
  }
  out
}

///|
test "an importing spec sees the imported types and routes" {
  let files : Map[String, String] = Map([
    (
      "spec/user.api",
      (
        #|type LoginReq {
        #|  name: string
        #|}
        #|@server(group: user, prefix: /api/v1)
        #|service greet {
        #|  @handler login
        #|  post /login (LoginReq)
        #|}
      ),
    ),
  ])
  let main =
    #|import "user.api"
    #|
    #|type PingResp {
    #|  ok: bool
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping returns (PingResp)
    #|}
  let spec = @api.parse_all(main, files, from="spec/greet.api")
  assert_eq(spec.service, "greet")
  // the import is merged in first, then the importing file's own
  assert_eq(type_names(spec), ["LoginReq", "PingResp"])
  assert_eq(spec.routes.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/login")
  assert_eq(spec.routes[0].req, "LoginReq")
  assert_eq(spec.routes[1].path, "/ping")
  assert_eq(spec.groups.length(), 1)
  assert_eq(spec.imports, ["spec/user.api"])
  // and the merged spec generates the imported type and route too
  let code = generate(spec)
  assert_eq(contains(code, "pub(all) struct LoginReq {"), true)
  assert_eq(
    contains(code, "app.post(\"/api/v1/login\", ctx => login(ctx))"),
    true,
  )
}

///|
test "an @server block groups its routes and prefixes their paths" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @doc "log a user in"
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|}
  let spec = @api.parse(src)
  assert_eq(spec.groups.length(), 1)
  assert_eq(spec.groups[0].name, "user")
  assert_eq(spec.groups[0].prefix, "/api/v1")
  assert_eq(spec.routes.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/ping")
  assert_eq(spec.routes[1].path, "/api/v1/login")
  match spec.routes[1].group {
    Some(g) => assert_eq(g.name, "user")
    None => fail("the route lost its group")
  }
  let code = generate(spec)
  assert_eq(contains(code, "// @server group: user, prefix: /api/v1"), true)
  assert_eq(contains(code, "app.get(\"/api/v1/ping\", ctx => ping(ctx))"), true)
  assert_eq(contains(code, "/// `post /api/v1/login` of group user."), true)
}

///|
test "a verb is lower-cased for the moonapi call it generates" {
  let spec = @api.parse("service greet {\n  GET /ping ping\n}")
  assert_eq(spec.routes[0].verb, "get")
  assert_eq(
    contains(generate(spec), "app.get(\"/ping\", ctx => ping(ctx))"),
    true,
  )
}

///|
test "the handlers a spec forgot to name still differ from one another" {
  let spec = @api.parse_lenient(
    (
      #|service greet {
      #|  get /ping
      #|  get /users/:id
      #|  post /users
      #|}
    ),
  )
  assert_eq(spec.routes[0].handler, "get_ping_handler")
  assert_eq(spec.routes[1].handler, "get_users_id_handler")
  assert_eq(spec.routes[2].handler, "post_users_handler")
  // three routes, three functions — one name declared twice would not compile
  let code = generate(spec)
  assert_eq(contains(code, "pub fn get_ping_handler("), true)
  assert_eq(contains(code, "pub fn get_users_id_handler("), true)
  assert_eq(contains(code, "pub fn post_users_handler("), true)
}

///|
test "a bare name inlines the block it names" {
  let src =
    #|type Base {
    #|  id: int64
    #|  ts: int64
    #|}
    #|
    #|type User {
    #|  Base
    #|  name: string
    #|}
  let spec = @api.parse(src)
  let user = spec.types[1]
  assert_eq(user.embeds, ["Base"])
  // the embed is not a field of its own
  assert_eq(user.fields.length(), 1)
  assert_eq(user.fields[0].name, "name")
  // MoonBit has no embedding, so the struct is the embedded fields then its own
  assert_eq(
    contains(
      generate(spec),
      (
        #|pub(all) struct User {
        #|  id : Int64
        #|  ts : Int64
        #|  name : String
        #|}
      ),
    ),
    true,
  )
}

///|
test "an embed of a block the spec never declared contributes nothing" {
  let spec = @api.parse("type User {\n  Missing\n  name: string\n}")
  assert_eq(spec.types[0].embeds, ["Missing"])
  assert_eq(
    contains(generate(spec), "pub(all) struct User {\n  name : String\n}"),
    true,
  )
}

///|
test "an embed leading back to a block already folded in stops there" {
  let src =
    #|type A {
    #|  B
    #|  a: int
    #|}
    #|
    #|type B {
    #|  A
    #|  b: int
    #|}
  let code = generate(@api.parse(src))
  assert_eq(
    contains(code, "pub(all) struct A {\n  b : Int32\n  a : Int32\n}"),
    true,
  )
  assert_eq(
    contains(code, "pub(all) struct B {\n  a : Int32\n  b : Int32\n}"),
    true,
  )
}

///|
test "an anonymous nested block becomes a type of its own" {
  let src =
    #|type Outer {
    #|  head: string
    #|  Inner `json:"inner"` {
    #|    a: int
    #|    b: string
    #|  }
    #|  tail: string
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = @api.parse(src)
  assert_eq(type_names(spec), ["Outer", "OuterInner"])
  // the block keeps every field it declared — the nested one closes itself, not its
  // parent, so what follows it is still the parent's
  assert_eq(spec.types[0].fields.length(), 3)
  assert_eq(spec.types[0].fields[0].name, "head")
  assert_eq(spec.types[0].fields[1].name, "Inner")
  assert_eq(spec.types[0].fields[1].type_, "OuterInner")
  assert_eq(spec.types[0].fields[1].json_name(), "inner")
  assert_eq(spec.types[0].fields[2].name, "tail")
  assert_eq(spec.types[1].fields.length(), 2)
  assert_eq(spec.types[1].fields[0].name, "a")
  // and the service that follows is still read as one
  assert_eq(spec.routes.length(), 1)
  let code = generate(spec)
  assert_eq(
    contains(
      code,
      (
        #|pub(all) struct Outer {
        #|  head : String
        #|  inner : OuterInner
        #|  tail : String
        #|}
      ),
    ),
    true,
  )
  assert_eq(contains(code, "pub(all) struct OuterInner {\n  a : Int32\n"), true)
}

///|
test "the grouped type form takes an embed and a nested block too" {
  let src =
    #|type (
    #|  Base {
    #|    id: int64
    #|  }
    #|
    #|  User {
    #|    Base
    #|    name: string
    #|  }
    #|)
  let spec = @api.parse(src)
  assert_eq(type_names(spec), ["Base", "User"])
  assert_eq(spec.types[1].embeds, ["Base"])
  assert_eq(
    contains(
      generate(spec),
      "pub(all) struct User {\n  id : Int64\n  name : String\n}",
    ),
    true,
  )
}

///|
test "generate compilable moonapi scaffolding" {
  let src =
    #|service greet {
    #|  get /ping ping "health check"
    #|  post /users create_user
    #|}
  let spec = @api.parse(src)
  let code = generate(spec)
  assert_eq(
    contains(
      code, "app.get(\"/ping\", ctx => ping(ctx), summary=\"health check\")",
    ),
    true,
  )
  assert_eq(
    contains(code, "app.post(\"/users\", ctx => create_user(ctx))"),
    true,
  )
  assert_eq(
    contains(
      code, "pub fn create_user(_ctx : @moonapi.Context) -> @moonasgi.Response",
    ),
    true,
  )
  assert_eq(contains(code, "pub fn build_app() -> @moonapi.App"), true)
  assert_eq(contains(code, "DO NOT EDIT"), true)
}

///|
test "generate structs from type blocks" {
  let src =
    #|type CreateReq {
    #|  name: string
    #|  age:  int
    #|}
    #|
    #|service greet {
    #|  post /users create_user
    #|}
  let code = generate(@api.parse(src))
  assert_eq(contains(code, "pub(all) struct CreateReq {"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(contains(code, "  age : Int"), true)
  assert_eq(contains(code, "pub fn build_app() -> @moonapi.App"), true)
}

///|
test "generate snake-cases PascalCase struct fields" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let code = generate(@api.parse(src))
  assert_eq(contains(code, "  user_name : String"), true)
}

///|
test "generate dispatches to the template engine when given one" {
  let spec = @api.parse("service greet {\n  get /ping ping\n}")
  let via_param = generate(spec, template="svc={{.service}}")
  assert_eq(via_param, "svc=greet")
  // Without a template it still emits the built-in scaffold.
  assert_eq(
    contains(generate(spec), "pub fn build_app() -> @moonapi.App"),
    true,
  )
}
