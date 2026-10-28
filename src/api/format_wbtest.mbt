///|
test "format lays a spec out one level at a time" {
  let messy =
    #|// greet service
    #|service   greet{
    #|get  /ping     ping   "health check"
    #|post /users (CreateReq) returns (User)
    #|}
    #|
    #|
    #|type CreateReq {
    #|name :string
    #|   age:   int
    #|}
  inspect(
    format(messy),
    content=(
      #|// greet service
      #|service greet {
      #|  get /ping ping "health check"
      #|  post /users (CreateReq) returns (User)
      #|}
      #|
      #|type CreateReq {
      #|  name: string
      #|  age: int
      #|}
      #|
    ),
  )
}

///|
test "a multi-line group keeps one setting a line, in key: value form" {
  let messy =
    #|@server (
    #|group:user,
    #|prefix:   /api/v1,
    #|   middleware: Log,Trace
    #|)
    #|service greet{
    #|@doc "log a user in"
    #|@handler login
    #|post /login (LoginReq) returns (LoginResp)
    #|}
  inspect(
    format(messy),
    content=(
      #|@server (
      #|  group: user,
      #|  prefix: /api/v1,
      #|  middleware: Log, Trace
      #|)
      #|service greet {
      #|  @doc "log a user in"
      #|  @handler login
      #|  post /login (LoginReq) returns (LoginResp)
      #|}
      #|
    ),
  )
}

///|
test "format is idempotent" {
  let messy =
    #|@server(group:user,  prefix:/api/v1)
    #|service   greet{
    #|  get /ping ping
    #|}
    #|type   User{
    #| id:int64 `json:"id"`
    #|}
  let once = format(messy)
  inspect(format(once), content=once)
}

///|
test "format keeps what the author wrote: comments, tags, blank-line spacing" {
  let src =
    #|
    #|type Link {
    #|  // where the link points
    #|  url: string `json:"url,default=http://example.com"`
    #|
    #|
    #|  note: string `json:"note,default=see: this"`
    #|}
  inspect(
    format(src),
    content=(
      #|type Link {
      #|  // where the link points
      #|  url: string `json:"url,default=http://example.com"`
      #|
      #|  note: string `json:"note,default=see: this"`
      #|}
      #|
    ),
  )
}

///|
test "format preserves what the spec means" {
  let src =
    #|@server(group: user, prefix: /api/v1, jwt: Auth)
    #|service greet {
    #|  @doc "log a user in"
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|
    #|  @handler ping
    #|  get /ping
    #|}
    #|
    #|type LoginReq {
    #|  name: string `json:"name"`
    #|  password: string `json:"password"`
    #|}
    #|
    #|type LoginResp {
    #|  token: string `json:"token"`
    #|}
  let before = parse(src)
  let after = parse(format(src))
  assert_eq(after.service, before.service)
  assert_eq(after.routes.length(), before.routes.length())
  assert_eq(after.types.length(), before.types.length())
  for i = 0; i < before.routes.length(); i = i + 1 {
    assert_eq(after.routes[i].verb, before.routes[i].verb)
    assert_eq(after.routes[i].path, before.routes[i].path)
    assert_eq(after.routes[i].handler, before.routes[i].handler)
    assert_eq(after.routes[i].req, before.routes[i].req)
    assert_eq(after.routes[i].resp, before.routes[i].resp)
    assert_eq(after.routes[i].summary, before.routes[i].summary)
  }
  for i = 0; i < before.types.length(); i = i + 1 {
    assert_eq(after.types[i].name, before.types[i].name)
    assert_eq(after.types[i].fields.length(), before.types[i].fields.length())
    for j = 0; j < before.types[i].fields.length(); j = j + 1 {
      assert_eq(after.types[i].fields[j].name, before.types[i].fields[j].name)
      assert_eq(after.types[i].fields[j].type_, before.types[i].fields[j].type_)
      assert_eq(after.types[i].fields[j].tag, before.types[i].fields[j].tag)
    }
  }
}
