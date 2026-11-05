///|
/// A spec with one request type bound from every place a request carries a value.
fn bound_spec() -> @api.Spec {
  @api.parse_lenient(
    (
      #|type CreateReq {
      #|  name: string `json:"name"`
      #|  age: int `json:"age"`
      #|  trace: string `header:"X-Trace"`
      #|  note?: string `json:"note"`
      #|}
      #|
      #|type PageReq {
      #|  page: int `form:"page"`
      #|  all?: bool `form:"all"`
      #|}
      #|
      #|service greet {
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
test "a binder reads each field from the place its tag names" {
  let code = render_binders(bound_spec())
  // the body member the tag names, read as the field's type
  assert_eq(contains(code, "match members.get(\"name\") {"), true)
  assert_eq(
    contains(code, "Some(@json.from_json(value))") ||
    contains(code, "@json.from_json(value)"),
    true,
  )
  // the header, from the request
  assert_eq(contains(code, "match ctx.request.header(\"X-Trace\") {"), true)
  // the query string, parsed with the helper its type needs
  assert_eq(contains(code, "match ctx.query(\"page\") {"), true)
  assert_eq(contains(code, "match bind_int32(text) {"), true)
  assert_eq(contains(code, "fn bind_int32(s : String) -> Int32? {"), true)
}

///|
test "a field that may be absent is not an error when it is missing" {
  let code = render_binders(bound_spec())
  // `note` is declared `note?`, so its body member may be missing
  assert_eq(contains(code, "let note : String? = match body {"), true)
  assert_eq(
    contains(code, "let all : Bool? = match ctx.query(\"all\") {"),
    true,
  )
  // the required ones say which field was missing
  assert_eq(contains(code, "header \\\"X-Trace\\\" is missing"), true)
}

///|
test "a binder is written only for the types a route declares" {
  let spec = @api.parse_lenient(
    (
      #|type Unused { id: int }
      #|
      #|type PingResp { ok: bool }
      #|
      #|service greet {
      #|  get /ping returns (PingResp)
      #|}
    ),
  )
  // nothing is bound, so the types package carries no binder and no helpers
  assert_eq(render_binders(spec), "")
  assert_eq(bound_types(spec).length(), 0)
}

///|
test "a request type the spec never declares is left unbound" {
  let spec = @api.parse_lenient("service greet {\n  post /x (Missing)\n}")
  assert_eq(bound_types(spec).length(), 0)
  assert_eq(render_binders(spec), "")
}

///|
test "only the helpers the fields need are emitted" {
  let spec = @api.parse_lenient(
    (
      #|type Q {
      #|  n: int `form:"n"`
      #|}
      #|
      #|service greet {
      #|  get /q (Q)
      #|}
    ),
  )
  let code = render_binders(spec)
  assert_eq(contains(code, "fn bind_int32"), true)
  assert_eq(contains(code, "fn bind_double"), false)
  assert_eq(contains(code, "fn bind_bool"), false)
}

///|
test "a field with no text form refuses where it is bound from text" {
  let spec = @api.parse_lenient(
    (
      #|type Q {
      #|  tags: []string `form:"tags"`
      #|}
      #|
      #|service greet {
      #|  get /q (Q)
      #|}
    ),
  )
  let code = render_binders(spec)
  assert_eq(contains(code, "has no text form; bind it from the body"), true)
  // and an optional one of the same type simply stays absent
  let optional = render_binders(
    @api.parse_lenient(
      (
        #|type Q {
        #|  tags?: []string `form:"tags"`
        #|}
        #|
        #|service greet {
        #|  get /q (Q)
        #|}
      ),
    ),
  )
  assert_eq(contains(optional, "let tags : Array[String]? = None"), true)
}
