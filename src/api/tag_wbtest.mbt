///|
test "parse goctl Go-struct fields with tags and pointers" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|  Age      int    `json:"age,optional"`
    #|  Cursor   *int64 `json:"cursor"`
    #|  Note     string
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let spec = parse(src)
  assert_eq(spec.types.length(), 1)
  let t = spec.types[0]
  assert_eq(t.fields.length(), 4)
  assert_eq(t.fields[0].name, "UserName")
  assert_eq(t.fields[0].type_, "String")
  assert_eq(t.fields[0].json_name(), "user_name")
  assert_eq(t.fields[1].json_name(), "age")
  assert_eq(t.fields[2].type_, "Int64?")
  assert_eq(t.fields[2].json_name(), "cursor")
  assert_eq(t.fields[3].tag, "")
  assert_eq(t.fields[3].json_name(), "Note")
}

///|
test "a tag naming several places binds from the leftmost" {
  let a = fields_of("type Q {\n  page: int `form:\"page\" json:\"page_no\"`\n}")
  inspect(bind_note(a[0]), content="query")
  assert_eq(a[0].json_name(), "page")
  // the other way round the json tag is the leftmost, so it is the one that binds
  let b = fields_of("type Q {\n  page: int `json:\"page_no\" form:\"page\"`\n}")
  inspect(bind_note(b[0]), content="body")
  assert_eq(b[0].json_name(), "page_no")
}

///|
test "a bound field is carried under the name its own tag gives" {
  let fs = fields_of(
    (
      #|type Filter {
      #|  region: string `path:"region"`
      #|  page:   int    `form:"page,optional"`
      #|  trace:  string `header:"X-Trace"`
      #|  note:   string
      #|}
    ),
  )
  assert_eq(fs[0].json_name(), "region")
  assert_eq(fs[1].json_name(), "page")
  assert_eq(fs[2].json_name(), "X-Trace")
  assert_eq(fs[3].json_name(), "note")
}

///|
test "a tag naming no field falls back to the field's own name" {
  let fs = fields_of("type Q {\n  page: int `form:\",optional\"`\n}")
  assert_eq(fs[0].json_name(), "page")
  assert_eq(fs[0].optional(), true)
}

///|
test "the options after the wire name are read" {
  let fs = fields_of(
    (
      #|type Query {
      #|  page:  int    `form:"page,default=1"`
      #|  size:  int    `form:"size,optional"`
      #|  sort:  string `form:"sort,options=asc|desc"`
      #|  email: string `json:"email,omitempty"`
      #|  plain: string `json:"plain"`
      #|}
    ),
  )
  assert_eq(fs[0].default_(), Some("1"))
  assert_eq(fs[0].optional(), false)
  assert_eq(fs[1].optional(), true)
  assert_eq(fs[1].default_(), None)
  assert_eq(fs[2].options(), ["asc", "desc"])
  // Go's own spelling of the same thing
  assert_eq(fs[3].optional(), true)
  assert_eq(fs[4].optional(), false)
  assert_eq(fs[4].options(), [])
}

///|
test "an options= list is trimmed, and an empty entry is not one of them" {
  let fs = fields_of("type Q {\n  s: string `form:\"s,options= a | b |\"`\n}")
  assert_eq(fs[0].options(), ["a", "b"])
}

///|
test "a tag whose body is never closed binds nothing" {
  let fs = fields_of("type Q {\n  page: int `form:\"page`\n}")
  inspect(bind_note(fs[0]), content="body")
  assert_eq(fs[0].json_name(), "page")
}

///|
test "the MoonBit spelling of a field is snake_case whatever the spec wrote" {
  let fs = fields_of(
    (
      #|type Account {
      #|  UserName string `json:"user_name"`
      #|  postID   int64
      #|}
    ),
  )
  // a MoonBit struct field has to start lower-case, so `UserName` cannot be one
  assert_eq(fs[0].mbt_name(), "user_name")
  assert_eq(fs[0].json_name(), "user_name")
  assert_eq(fs[1].mbt_name(), "post_id")
  // and the wire name is the tag's, which need not agree with either
  assert_eq(fs[1].json_name(), "postID")
}
