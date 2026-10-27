///|
/// Look up a string-valued key in a JSON object, or `""` if absent / not a string.
fn jstr(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Look up an object-valued key, or an empty map if absent / not an object.
fn jobj(obj : Map[String, Json], key : String) -> Map[String, Json] {
  match obj.get(key) {
    Some(Object(m)) => m
    _ => Map([])
  }
}

///|
/// Look up an array-valued key, or an empty array if absent / not an array.
fn jarr(obj : Map[String, Json], key : String) -> Array[Json] {
  match obj.get(key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// The strings of an array-valued key, in order.
fn jstrs(obj : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for it in jarr(obj, key) {
    match it {
      String(s) => out.push(s)
      _ => ()
    }
  }
  out
}

///|
/// Look up a boolean-valued key, or `None` if absent / not a boolean.
fn jbool(obj : Map[String, Json], key : String) -> Bool? {
  match obj.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// Look up a number-valued key, or `None` if absent / not a number.
fn jnum(obj : Map[String, Json], key : String) -> Double? {
  match obj.get(key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// The `i`th element of `arr` as an object, or an empty map.
fn jat(arr : Array[Json], i : Int32) -> Map[String, Json] {
  match arr[i] {
    Object(m) => m
    _ => Map([])
  }
}

///|
/// The document `src` generates, as its root object.
fn document(src : String, version : DocVersion) -> Map[String, Json] raise {
  match @json.loads(generate_doc(@api.parse(src), version~)) {
    Object(m) => m
    _ => Map([])
  }
}

///|
/// The operation `verb path` of a generated document.
fn operation(
  root : Map[String, Json],
  path : String,
  verb : String,
) -> Map[String, Json] {
  jobj(jobj(jobj(root, "paths"), path), verb)
}

///|
/// The component schema named `name`, wherever this version keeps it.
fn schema_of(root : Map[String, Json], name : String) -> Map[String, Json] {
  if root.contains("definitions") {
    jobj(jobj(root, "definitions"), name)
  } else {
    jobj(jobj(jobj(root, "components"), "schemas"), name)
  }
}

///|
/// A request type whose fields bind from every place a tag can name.
let bound_src : String =
  #|type ListReq {
  #|  region: string `path:"region"`
  #|  page:   int    `form:"page,default=1,range=[1:100]"`
  #|  size:   int    `form:"size,optional"`
  #|  trace:  string `header:"X-Trace"`
  #|}
  #|
  #|service greet {
  #|  @handler list
  #|  get /regions/:region/items (ListReq)
  #|}

///|
fn contains(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
test "Swagger 2.0 uses definitions and inline path-param type" {
  let src =
    #|service s {
    #|  get /items/:id show
    #|}
    #|type Item {
    #|  id: int
    #|}
  let js = generate_doc(@api.parse(src), version=Swagger20)
  let root = match @json.loads(js) {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(root, "swagger"), "2.0")
  // 2.0 hoists schemas under `definitions`, not `components/schemas`
  assert_eq(root.contains("definitions"), true)
  assert_eq(root.contains("components"), false)
  assert_eq(jobj(root, "definitions").contains("Item"), true)
  // 2.0 puts the path-param type inline (no `schema` wrapper)
  let show = jobj(jobj(jobj(root, "paths"), "/items/{id}"), "get")
  let p0 = match show.get("parameters") {
    Some(Array([Object(m), ..])) => m
    _ => Map([])
  }
  assert_eq(jstr(p0, "type"), "string")
  assert_eq(p0.contains("schema"), false)
}

///|
test "component schema types: array items, map additionalProperties, $ref" {
  let src =
    #|type Bag {
    #|  tags:  []string
    #|  attrs: map[string]int64
    #|  owner: User
    #|}
    #|type User {
    #|  id: int64
    #|}
  let js = generate_doc(@api.parse(src), version=OpenApi30)
  let root = match @json.loads(js) {
    Object(m) => m
    _ => Map([])
  }
  let bag = jobj(jobj(jobj(root, "components"), "schemas"), "Bag")
  let props = jobj(bag, "properties")
  let tags = jobj(props, "tags")
  assert_eq(jstr(tags, "type"), "array")
  assert_eq(jstr(jobj(tags, "items"), "type"), "string")
  let attrs = jobj(props, "attrs")
  assert_eq(jstr(attrs, "type"), "object")
  assert_eq(jstr(jobj(attrs, "additionalProperties"), "format"), "int64")
  // an unknown type name is another `type` block -> a $ref
  assert_eq(jstr(jobj(props, "owner"), "$ref"), "#/components/schemas/User")
}

///|
test "a form field is a query parameter and a path field takes its tag's name" {
  let root = document(bound_src, OpenApi31)
  let op = operation(root, "/regions/{region}/items", "get")
  let ps = jarr(op, "parameters")
  assert_eq(ps.length(), 4)
  assert_eq(jstr(jat(ps, 0), "name"), "region")
  assert_eq(jstr(jat(ps, 0), "in"), "path")
  assert_eq(jstr(jat(ps, 1), "name"), "page")
  assert_eq(jstr(jat(ps, 1), "in"), "query")
  assert_eq(jstr(jat(ps, 2), "name"), "size")
  assert_eq(jstr(jat(ps, 2), "in"), "query")
  assert_eq(jstr(jat(ps, 3), "name"), "X-Trace")
  assert_eq(jstr(jat(ps, 3), "in"), "header")
  // a path segment is always required; elsewhere the tag decides. There are four
  // parameters and not five, so the `:region` segment a field already named is not
  // documented twice
  assert_eq(jbool(jat(ps, 0), "required"), Some(true))
  assert_eq(jbool(jat(ps, 1), "required"), Some(true))
  assert_eq(jbool(jat(ps, 2), "required"), Some(false))
  // and nothing is left to carry in the body
  assert_eq(op.contains("requestBody"), false)
  // the query parameter keeps the constraints its tag declared
  let page = jobj(jat(ps, 1), "schema")
  assert_eq(jnum(page, "default"), Some(1.0))
  assert_eq(jnum(page, "minimum"), Some(1.0))
  assert_eq(jnum(page, "maximum"), Some(100.0))
}

///|
test "Swagger 2.0 puts a bound field's type beside it, not under a schema" {
  let root = document(bound_src, Swagger20)
  let ps = jarr(operation(root, "/regions/{region}/items", "get"), "parameters")
  let page = jat(ps, 1)
  assert_eq(jstr(page, "type"), "integer")
  assert_eq(jnum(page, "maximum"), Some(100.0))
  assert_eq(page.contains("schema"), false)
}

///|
test "a request type with a body of its own still documents one" {
  let src =
    #|type MixedReq {
    #|  region: string `path:"region"`
    #|  name:   string `json:"name"`
    #|}
    #|
    #|service greet {
    #|  @handler put_one
    #|  post /regions/:region (MixedReq)
    #|}
  let op = operation(document(src, OpenApi31), "/regions/{region}", "post")
  assert_eq(jarr(op, "parameters").length(), 1)
  assert_eq(op.contains("requestBody"), true)
  // a type the spec never declared says nothing about where its fields bind, so the
  // request body it names is documented rather than dropped
  let bare = operation(
    document(
      "service greet {\n  @handler post_x\n  post /x (Unknown)\n}",
      OpenApi31,
    ),
    "/x",
    "post",
  )
  assert_eq(bare.contains("requestBody"), true)
}

///|
test "the tag's constraints reach the schema" {
  let src =
    #|type CreateReq {
    #|  name: string `json:"name"`
    #|  nick: string `json:"nick,optional"`
    #|  role: string `json:"role,options=admin|user"`
    #|  age:  int    `json:"age,default=18,range=(0:150]"`
    #|}
  let req = schema_of(document(src, OpenApi31), "CreateReq")
  // everything no tag marked optional is required
  assert_eq(jstrs(req, "required"), ["name", "role", "age"])
  let props = jobj(req, "properties")
  assert_eq(jstrs(jobj(props, "role"), "enum"), ["admin", "user"])
  let age = jobj(props, "age")
  assert_eq(jnum(age, "default"), Some(18.0))
  // 3.1 spells an exclusive bound as the number itself
  assert_eq(jnum(age, "exclusiveMinimum"), Some(0.0))
  assert_eq(jnum(age, "maximum"), Some(150.0))
  assert_eq(age.contains("minimum"), false)
  // a `path:`/`form:`/`header:` field is a parameter, so it is not a body property
  assert_eq(
    schema_of(document(bound_src, OpenApi31), "ListReq").contains("properties"),
    true,
  )
  assert_eq(
    jobj(schema_of(document(bound_src, OpenApi31), "ListReq"), "properties").length(),
    0,
  )
}

///|
test "3.0 spells an exclusive bound as a flag beside an inclusive one" {
  let src = "type Q {\n  age: int `json:\"age,range=(0:150]\"`\n}"
  let age = jobj(
    jobj(schema_of(document(src, OpenApi30), "Q"), "properties"),
    "age",
  )
  assert_eq(jnum(age, "minimum"), Some(0.0))
  assert_eq(jbool(age, "exclusiveMinimum"), Some(true))
  assert_eq(jnum(age, "maximum"), Some(150.0))
}

///|
test "an embedded block is documented as the allOf it serialises to" {
  let src =
    #|type Base {
    #|  id: int64 `json:"id"`
    #|}
    #|
    #|type User {
    #|  Base
    #|  name: string `json:"name"`
    #|}
  let user = schema_of(document(src, OpenApi31), "User")
  let all = jarr(user, "allOf")
  assert_eq(all.length(), 2)
  assert_eq(jstr(jat(all, 0), "$ref"), "#/components/schemas/Base")
  assert_eq(jobj(jat(all, 1), "properties").contains("name"), true)
}

///|
test "a Bool constraint is documented as a boolean, not as its spelling" {
  let ok = jobj(
    jobj(
      schema_of(
        document(
          "type Q {\n  ok: bool `json:\"ok,default=true,options=true|false\"`\n}",
          OpenApi31,
        ),
        "Q",
      ),
      "properties",
    ),
    "ok",
  )
  assert_eq(jbool(ok, "default"), Some(true))
  assert_eq(jarr(ok, "enum"), [Json(true), Json(false)])
  // a numeric field's option that does not read as a number stays the text it was
  let n = jobj(
    jobj(
      schema_of(
        document("type N {\n  n: int `json:\"n,default=abc\"`\n}", OpenApi31),
        "N",
      ),
      "properties",
    ),
    "n",
  )
  assert_eq(jstr(n, "default"), "abc")
}

///|
test "a field pointing at another message carries nothing beside its $ref" {
  let src =
    #|type Inner {
    #|  a: int
    #|}
    #|
    #|type Outer {
    #|  inner: Inner `json:"inner,default=x,options=p|q"`
    #|}
  let inner = jobj(
    jobj(schema_of(document(src, OpenApi31), "Outer"), "properties"),
    "inner",
  )
  // a `$ref` may not be qualified by siblings, so the constraints are dropped
  assert_eq(jstr(inner, "$ref"), "#/components/schemas/Inner")
  assert_eq(inner.length(), 1)
}

///|
test "a block that declares nothing of its own is only what it inlined" {
  let src =
    #|type Base {
    #|  id: int64 `json:"id"`
    #|}
    #|
    #|type User {
    #|  Base
    #|}
  let all = jarr(schema_of(document(src, OpenApi31), "User"), "allOf")
  assert_eq(all.length(), 1)
  assert_eq(jstr(jat(all, 0), "$ref"), "#/components/schemas/Base")
}

///|
test "a block nothing is required of does not say so" {
  let q = schema_of(
    document("type Q {\n  a: string `json:\"a,optional\"`\n}", OpenApi31),
    "Q",
  )
  assert_eq(q.contains("required"), false)
  assert_eq(jobj(q, "properties").contains("a"), true)
}

///|
test "a request whose body comes from what it inlined is still a body" {
  let src =
    #|type Base {
    #|  name: string `json:"name"`
    #|}
    #|
    #|type CreateReq {
    #|  Base
    #|  page: int `form:"page"`
    #|}
    #|
    #|service greet {
    #|  @handler create
    #|  post /users (CreateReq)
    #|}
  let op = operation(document(src, OpenApi31), "/users", "post")
  assert_eq(op.contains("requestBody"), true)
  // and the query field is still a parameter of its own
  assert_eq(jarr(op, "parameters").length(), 1)
}

///|
test "swagger UI stub points at the served spec" {
  let html = swagger_ui_stub(spec_url="/openapi.json", title="greet")
  assert_eq(contains(html, "<title>greet</title>"), true)
  assert_eq(contains(html, "url: \"/openapi.json\""), true)
  assert_eq(contains(html, "SwaggerUIBundle"), true)
}

///|
test "a group becomes the OpenAPI tag of its operations" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let doc = openapi_document(@api.parse(src), version=OpenApi31).stringify()
  assert_eq(contains(doc, "\"/api/v1/ping\""), true)
  assert_eq(contains(doc, "\"operationId\":\"ping\",\"tags\":[\"user\"]"), true)
  assert_eq(contains(doc, "\"tags\":[{\"name\":\"user\"}]"), true)
}

///|
test "parse modern route grammar with @handler @doc and typed Req/Resp" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|type LoginResp {
    #|  Token string `json:"token"`
    #|}
    #|
    #|service greet {
    #|  @doc "log a user in"
    #|  @handler login
    #|  post /users/login (LoginReq) returns (LoginResp)
    #|}
  let spec = @api.parse(src)
  assert_eq(spec.routes.length(), 1)
  let r = spec.routes[0]
  assert_eq(r.verb, "post")
  assert_eq(r.path, "/users/login")
  assert_eq(r.handler, "login")
  assert_eq(r.summary, "log a user in")
  assert_eq(r.req, "LoginReq")
  assert_eq(r.resp, "LoginResp")
  let doc = openapi_document(spec, version=OpenApi31).stringify()
  assert_eq(contains(doc, "requestBody"), true)
  assert_eq(contains(doc, "#/components/schemas/LoginReq"), true)
  assert_eq(contains(doc, "#/components/schemas/LoginResp"), true)
}

///|
test "parse skips syntax and captures the info block into the OpenAPI info" {
  let src =
    #|syntax = "v1"
    #|
    #|info (
    #|  title:   "Greet API"
    #|  desc:    "qwq service"
    #|  version: "v2"
    #|)
    #|
    #|service greet {
    #|  get /ping ping "health check"
    #|}
  let spec = @api.parse(src)
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.routes[0].handler, "ping")
  assert_eq(info_get(spec, "title"), Some("Greet API"))
  assert_eq(info_get(spec, "desc"), Some("qwq service"))
  assert_eq(info_get(spec, "version"), Some("v2"))
  let doc = openapi_document(spec, version=OpenApi31).stringify()
  assert_eq(contains(doc, "Greet API"), true)
  assert_eq(contains(doc, "qwq service"), true)
  assert_eq(contains(doc, "v2"), true)
}

///|
test "openapi property name comes from the json tag" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let doc = openapi_document(@api.parse(src), version=OpenApi31).stringify()
  assert_eq(contains(doc, "user_name"), true)
}
