///|
/// A spec whose routes carry a request type, an optional field, a list, and one
/// route with nothing to send.
fn mcp_spec() -> @api.Spec {
  @api.parse_lenient(
    (
      #|type CreateReq {
      #|  name: string `json:"name"`
      #|  age: int `json:"age"`
      #|  note?: string `json:"note"`
      #|  tags: []string `json:"tags"`
      #|}
      #|
      #|type PageReq {
      #|  page: int `form:"page"`
      #|}
      #|
      #|service catalog {
      #|  @doc "Say hello"
      #|  @handler hello
      #|  get /hello
      #|
      #|  @handler create
      #|  post /items (CreateReq)
      #|
      #|  @handler list
      #|  get /items (PageReq)
      #|}
    ),
  )
}

///|
fn scaffold_contains(hay : String, needle : String) -> Bool {
  hay.contains(needle)
}

///|
test "every route with a request type is an annotated tool" {
  let tools = mcp_tools_for(mcp_spec())
  // one `#mcp.tool` per route that has something to send
  assert_eq(
    scaffold_contains(tools, "#mcp.tool(description=\"post /items\")"),
    true,
  )
  assert_eq(
    scaffold_contains(tools, "#mcp.tool(description=\"get /items\")"),
    true,
  )
  // the request fields are the parameters, an optional one marked `?`
  assert_eq(scaffold_contains(tools, "  name : String,\n"), true)
  assert_eq(scaffold_contains(tools, "  note? : String,\n"), true)
  assert_eq(scaffold_contains(tools, "  tags : Array[String],\n"), true)
  // a route with nothing to send is not offered, and says so through `mcp_skipped`
  assert_eq(scaffold_contains(tools, "pub fn hello("), false)
  assert_eq(mcp_skipped(mcp_spec()), ["get /hello"])
}

///|
test "the registration mirrors what moonmcp writes, so a fresh project compiles" {
  let registration = mcp_registration_for(mcp_spec())
  assert_eq(
    scaffold_contains(registration, "pub fn register(mcp : @moonmcp.Server)"),
    true,
  )
  // a required argument is decoded, an optional one through `decode_option`
  assert_eq(
    scaffold_contains(registration, "@moonmcp.decode(args, \"name\")"),
    true,
  )
  assert_eq(
    scaffold_contains(
      registration, "note?=@moonmcp.decode_option(args, \"note\")",
    ),
    true,
  )
  // and the schema names the same properties, with the required ones listed
  assert_eq(
    scaffold_contains(registration, "\"name\": { \"type\": \"string\" }"),
    true,
  )
  assert_eq(
    scaffold_contains(registration, "\"age\": { \"type\": \"integer\" }"),
    true,
  )
  assert_eq(
    scaffold_contains(
      registration, "\"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}},",
    ),
    true,
  )
  assert_eq(
    scaffold_contains(
      registration, "\"required\": [\"name\", \"age\", \"tags\"]",
    ),
    true,
  )
}

///|
test "two routes under one handler name are numbered, not declared twice" {
  let spec = @api.parse_lenient(
    (
      #|type Q {
      #|  id: int
      #|}
      #|
      #|service greet {
      #|  @handler dup
      #|  get /a (Q)
      #|
      #|  @handler dup
      #|  get /b (Q)
      #|}
    ),
  )
  let tools = mcp_tools_for(spec)
  assert_eq(scaffold_contains(tools, "pub fn dup("), true)
  assert_eq(scaffold_contains(tools, "pub fn dup_2("), true)
  assert_eq(scaffold_contains(mcp_registration_for(spec), "\"dup_2\""), true)
}

///|
test "a type with no schema of its own travels as JSON text" {
  let spec = @api.parse_lenient(
    (
      #|type Inner {
      #|  a: int
      #|}
      #|
      #|type Q {
      #|  outer: Inner
      #|}
      #|
      #|service greet {
      #|  @handler put
      #|  post /x (Q)
      #|}
    ),
  )
  let tools = mcp_tools_for(spec)
  assert_eq(scaffold_contains(tools, "  outer : String,\n"), true)
  assert_eq(
    scaffold_contains(
      mcp_registration_for(spec),
      "\"outer\": { \"type\": \"string\", \"description\": \"JSON text\" }",
    ),
    true,
  )
}

///|
test "the seeded test counts the tools the server offers" {
  let checks = mcp_checks_for(mcp_spec())
  assert_eq(scaffold_contains(checks, "assert_eq(list.length(), 2)"), true)
}

///|
test "the tree carries the tools, their registration and the build rule" {
  let tree = generate_mcp_from_spec(mcp_spec(), dir="out")
  let mut tools = ""
  let mut registration = ""
  let mut rule = ""
  for f in tree {
    if f.path == "out/internal/tools/tools.mbt" {
      tools = f.content
    }
    if f.path == "out/internal/tools/tools.g.mbt" {
      registration = f.content
    }
    if f.path == "out/moon.mod" {
      rule = f.content
    }
  }
  assert_eq(scaffold_contains(tools, "#mcp.tool("), true)
  assert_eq(scaffold_contains(registration, "mcp.tool("), true)
  // the module wires moonmcp's generator in, which is what rebuilds the registration
  assert_eq(
    scaffold_contains(rule, "moonx moonbitstack/moonmcp/cmd/mcp@"),
    true,
  )
  assert_eq(scaffold_contains(rule, "name: \"mcp\","), true)
}
