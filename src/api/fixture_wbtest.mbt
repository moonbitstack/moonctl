///|
/// The parser's complaint about `src`, or "" when it reads cleanly.
fn complaint(src : String) -> String {
  try parse(src) |> ignore catch {
    e => Show::to_string(e)
  } noraise {
    _ => ""
  }
}

///|
/// Every complaint the parser has about `src`, one per line, in the order it made
/// them — `complaint` shows only the earliest.
fn complaints(src : String) -> String {
  let mut out = ""
  for it in read(src).1 {
    let one = "line " + it.0.to_string() + ": " + it.1
    out = if out == "" { one } else { out + "\n" + one }
  }
  out
}

///|
/// The fields of the first `type` block `src` declares.
fn fields_of(src : String) -> Array[Field] raise SpecError {
  parse(src).types[0].fields
}

///|
/// A field's `range=` written back the way the tag spelled it, or "none".
fn range_note(f : Field) -> String {
  match f.range() {
    Some(r) =>
      (if r.lo_inc { "[" } else { "(" }) +
      r.lo +
      ":" +
      r.hi +
      (if r.hi_inc { "]" } else { ")" })
    None => "none"
  }
}

///|
/// Where a field binds from, as a word.
fn bind_note(f : Field) -> String {
  match f.bind() {
    Body => "body"
    Query => "query"
    Path => "path"
    Header => "header"
  }
}

///|
test "an unreadable import is reported" {
  inspect(
    complaint("import user.api\nservice greet {\n}"),
    content="line 1: import needs a quoted path",
  )
  inspect(
    complaint("import (\n  user.api\n)\nservice greet {\n}"),
    content="line 2: expected a quoted path in the import group, got \"user.api\"",
  )
  inspect(
    complaint("import (\n  \"a.api\"\nservice greet {\n}"),
    content="line 1: import block is missing its closing `)`",
  )
}

///|
test "a misspelt verb is reported with its line" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  get /ping ping
        #|  gett /pong pong
        #|}
      ),
    ),
    content="line 3: unknown verb \"gett\"",
  )
}

///|
test "a misspelt annotation is reported with its line" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  @hadler login
        #|  post /login
        #|}
      ),
    ),
    content="line 2: unknown annotation \"@hadler\"",
  )
}

///|
test "a block left open is reported at the line that opened it" {
  inspect(
    complaint(
      (
        #|type User {
        #|  id: int64
        #|
        #|service greet {
        #|  get /ping ping
        #|}
      ),
    ),
    content="line 1: type User is missing its closing `}`",
  )
  inspect(
    complaint("service greet {\n  get /ping ping\n"),
    content="line 1: service greet is missing its closing `}`",
  )
  inspect(
    complaint("@server (\n  group: user\nservice greet {\n}"),
    content="line 1: @server block is missing its closing `)`",
  )
}

///|
test "a field with no type is reported" {
  inspect(
    complaint("type User {\n  id:\n}"),
    content="line 2: field \"id:\" in type User has no type",
  )
  // a bare name is goctl's inline embed, so only a line that names nothing is one
  inspect(
    complaint("type User {\n  42\n}"),
    content="line 2: field \"42\" in type User has no type",
  )
  inspect(
    complaint("type User {\n  a-b\n}"),
    content="line 2: field \"a-b\" in type User has no type",
  )
}

///|
test "a route with no handler is reported" {
  inspect(
    complaint("service greet {\n  get /ping\n}"),
    content="line 2: route get /ping has no handler; name one with `@handler`",
  )
  inspect(
    complaint("service greet {\n  @handler ping\n}"),
    content="line 3: @handler ping has no route",
  )
}

///|
test "a misspelt @doc key is named rather than dropped" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  @doc (
        #|    sumary: "log a user in"
        #|  )
        #|  @handler login
        #|  post /login
        #|}
      ),
    ),
    content="line 3: @doc entry \"sumary\" is not summary or description",
  )
  // an unclosed block runs to the end of the file, so the service is left open too
  inspect(
    complaints("service greet {\n  @doc (\n  @handler login\n  post /login\n}"),
    content=(
      #|line 2: @doc block is missing its closing `)`
      #|line 1: service greet is missing its closing `}`
    ),
  )
}

///|
test "an annotation that merely starts with a known one is not that one" {
  inspect(
    complaint("service greet {\n  @docs \"text\"\n  @handler a\n  get /a\n}"),
    content="line 2: unknown annotation \"@docs\"",
  )
}

///|
test "a malformed @server annotation is reported" {
  inspect(
    complaint("@server(group: user, maxBytes: lots)\nservice greet {\n}"),
    content="line 1: maxBytes: expected a number, got \"lots\"",
  )
  inspect(
    complaint("@server(signature: yes)\nservice greet {\n}"),
    content="line 1: signature: expected true or false, got \"yes\"",
  )
}

///|
test "a multi-line @server names the entry's own line, not the block's" {
  inspect(
    complaint(
      (
        #|@server (
        #|  group:    user
        #|
        #|  // the request cap
        #|  maxBytes: lots
        #|)
        #|service greet {
        #|}
      ),
    ),
    content="line 5: maxBytes: expected a number, got \"lots\"",
  )
  inspect(
    complaint("@server (\n  nonsense\n  group: user\n)\nservice greet {\n}"),
    content="line 2: @server entry \"nonsense\" is not `key: value`",
  )
}

///|
test "a nested block left open is reported against the block that opened it" {
  inspect(
    complaint(
      (
        #|type Outer {
        #|  Inner {
        #|    a: int
        #|}
      ),
    ),
    content="line 1: type Outer is missing its closing `}`",
  )
  inspect(
    complaint(
      (
        #|type Outer {
        #|  Inner {
        #|    a: int
        #|  }
      ),
    ),
    content="line 1: type Outer is missing its closing `}`",
  )
}

///|
test "a field binds where its tag says it does" {
  let fs = fields_of(
    (
      #|type Filter {
      #|  region: string `path:"region"`
      #|  page:   int    `form:"page"`
      #|  trace:  string `header:"X-Trace"`
      #|  name:   string `json:"name"`
      #|  note:   string
      #|}
    ),
  )
  inspect(bind_note(fs[0]), content="path")
  inspect(bind_note(fs[1]), content="query")
  inspect(bind_note(fs[2]), content="header")
  inspect(bind_note(fs[3]), content="body")
  // an untagged field reads out of the body too
  inspect(bind_note(fs[4]), content="body")
}

///|
test "a range keeps its bounds and which end is closed" {
  let fs = fields_of(
    (
      #|type Query {
      #|  age:   int     `form:"age,range=[1:120]"`
      #|  ratio: float64 `form:"ratio,range=(0:1)"`
      #|  from:  int64   `form:"from,range=[10:]"`
      #|  plain: int     `form:"plain"`
      #|}
    ),
  )
  inspect(range_note(fs[0]), content="[1:120]")
  inspect(range_note(fs[1]), content="(0:1)")
  // an open end is empty, not absent
  inspect(range_note(fs[2]), content="[10:]")
  inspect(range_note(fs[3]), content="none")
}

///|
test "a range= with no brackets is not a range" {
  let fs = fields_of("type Q {\n  n: int `form:\"n,range=1:100\"`\n}")
  inspect(range_note(fs[0]), content="none")
  // and neither is one with no colon between the bounds
  let m = fields_of("type Q {\n  n: int `form:\"n,range=[1100]\"`\n}")
  inspect(range_note(m[0]), content="none")
}
