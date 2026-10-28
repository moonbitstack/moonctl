///|
/// Every finding for a spec, one per line, the way `mctl api validate` prints them.
fn report(src : String) -> String {
  let mut out = ""
  for d in validate_source(src) {
    if out != "" {
      out = out + "\n"
    }
    out = out + Show::to_string(d)
  }
  out
}

///|
/// Whether a spec is reported with `rule` at all.
fn reports(src : String, rule : String) -> Bool {
  for d in validate_source(src) {
    if d.rule == rule {
      return true
    }
  }
  false
}

///|
test "a spec that holds together has nothing to report" {
  let src =
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @handler create
    #|  post /users (CreateReq) returns (User)
    #|}
    #|
    #|type CreateReq {
    #|  name: string `json:"name"`
    #|}
    #|
    #|type User {
    #|  id: int64 `json:"id"`
    #|  tags: []string `json:"tags"`
    #|}
  inspect(report(src), content="")
}

///|
test "a route naming a type nobody declared is an error" {
  let src =
    #|service greet {
    #|  @handler create
    #|  post /users (CreateReq) returns (User)
    #|}
  inspect(
    report(src),
    content=(
      #|error [unknown-type] post /users: request type "CreateReq" is not declared
      #|error [unknown-type] post /users: response type "User" is not declared
    ),
  )
}

///|
test "two routes under one handler or on one verb and path are errors" {
  let src =
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @handler ping
    #|  get /ping
    #|}
  inspect(
    report(src),
    content=(
      #|error [duplicate-handler] get /ping: handler "ping" is declared by more than one route
      #|error [duplicate-route] get /ping: the same verb and path is declared twice
    ),
  )
}

///|
test "a handler named after a keyword would not compile" {
  let src =
    #|service greet {
    #|  @handler test
    #|  get /ping
    #|}
  inspect(
    report(src),
    content=(
      #|error [reserved-handler] get /ping: "test" is a MoonBit keyword, so the generated function cannot carry it
    ),
  )
}

///|
test "a path parameter with no field behind it is a warning" {
  let src =
    #|service users {
    #|  @handler get_one
    #|  get /users/:id (GetReq)
    #|}
    #|
    #|type GetReq {
    #|  field: string `json:"field"`
    #|}
  inspect(
    report(src),
    content=(
      #|warning [path-param] get /users/:id: `:id` has no field named "id" in GetReq, so nothing fills it
    ),
  )
  // tagging a field `path:"id"` is what makes the segment bindable
  let bound =
    #|service users {
    #|  @handler get_one
    #|  get /users/:id (GetReq)
    #|}
    #|
    #|type GetReq {
    #|  id: int64 `path:"id"`
    #|}
  assert_eq(reports(bound, "path-param"), false)
}

///|
test "a type declared twice, a field declared twice, a field of an unknown type" {
  let src =
    #|service greet {
    #|  @handler ping
    #|  get /ping (Req)
    #|}
    #|
    #|type Req {
    #|  id: int64
    #|  id: string
    #|  owner: Owner
    #|}
    #|
    #|type Req {
    #|  again: string
    #|}
  let errors = report(src)
  assert_eq(errors.contains("duplicate-type"), true)
  assert_eq(errors.contains("duplicate-field"), true)
  assert_eq(errors.contains("field type \"Owner\" is not declared"), true)
}

///|
test "a block nobody refers to, and a service with no route, are warnings" {
  let src =
    #|service greet {
    #|}
    #|
    #|type Orphan {
    #|  id: int64
    #|}
  inspect(
    report(src),
    content=(
      #|warning [empty-service] service greet: the service declares no route
      #|warning [unused-type] type Orphan: no route and no other type refers to it
    ),
  )
}

///|
test "a group that annotates no route is a warning" {
  let src =
    #|@server(group: admin, prefix: /admin)
    #|@server(group: public)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  inspect(
    report(src),
    content=(
      #|warning [unused-group] @server(admin): the group annotates no route
    ),
  )
}

///|
test "a spec the parser cannot read is one finding, not a raise" {
  let src = "service greet {\n  gett /ping ping\n}"
  inspect(report(src), content="error [syntax] line 2: unknown verb \"gett\"")
  assert_eq(has_errors(validate_source(src)), true)
}

///|
test "an embedded type counts as declared and used" {
  let src =
    #|service greet {
    #|  @handler create
    #|  post /users (CreateReq) returns (User)
    #|}
    #|
    #|type Base {
    #|  id: int64 `json:"id"`
    #|}
    #|
    #|type CreateReq {
    #|  Base
    #|  name: string `json:"name"`
    #|}
    #|
    #|type User {
    #|  Base
    #|}
  inspect(report(src), content="")
}

///|
test "the rules that fired are the ones named" {
  let src =
    #|service greet {
    #|  @handler ping
    #|  get /ping (Missing)
    #|}
  let found = validate_source(src)
  assert_eq(found.length(), 1)
  assert_eq(found[0].severity == Error, true)
  assert_eq(has_errors(found), true)
  assert_eq(found[0].at, "get /ping")
}
