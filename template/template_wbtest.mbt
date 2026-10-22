///|
fn dict(entries : Array[(String, Value)]) -> Value {
  Dict(Map(entries))
}

///|
test "interpolation substitutes fields" {
  let out = render("Hello {{.name}}!", dict([("name", Str("world"))]))
  assert_eq(out, "Hello world!")
  // Mutation guard: a no-op engine would echo the template verbatim.
  assert_eq(out == "Hello {{.name}}!", false)
}

///|
test "nested field access" {
  let data = dict([("user", dict([("name", Str("ada"))]))])
  assert_eq(render("{{.user.name}}", data), "ada")
}

///|
test "dot refers to the current value" {
  assert_eq(render("<{{.}}>", Str("x")), "<x>")
}

///|
test "missing key renders empty and is falsy" {
  let data = dict([("a", Str("A"))])
  assert_eq(render("[{{.missing}}]", data), "[]")
  assert_eq(render("{{if .missing}}Y{{else}}N{{end}}", data), "N")
}

///|
test "if / else branch on truthiness" {
  assert_eq(
    render("{{if .ok}}yes{{else}}no{{end}}", dict([("ok", Bool(true))])),
    "yes",
  )
  assert_eq(
    render("{{if .ok}}yes{{else}}no{{end}}", dict([("ok", Bool(false))])),
    "no",
  )
  // empty string / zero / empty list are falsy
  assert_eq(render("{{if .s}}Y{{else}}N{{end}}", dict([("s", Str(""))])), "N")
  assert_eq(render("{{if .n}}Y{{else}}N{{end}}", dict([("n", Int(0L))])), "N")
}

///|
test "else if chains" {
  let tmpl = "{{if lt .n 0}}neg{{else if eq .n 0}}zero{{else}}pos{{end}}"
  assert_eq(render(tmpl, dict([("n", Int(-5L))])), "neg")
  assert_eq(render(tmpl, dict([("n", Int(0L))])), "zero")
  assert_eq(render(tmpl, dict([("n", Int(7L))])), "pos")
}

///|
test "range over a list binds dot to each element" {
  let data = dict([("xs", List([Str("a"), Str("b"), Str("c")]))])
  assert_eq(render("{{range .xs}}[{{.}}]{{end}}", data), "[a][b][c]")
}

///|
test "range with index and value variables" {
  let data = dict([("xs", List([Str("a"), Str("b")]))])
  assert_eq(
    render("{{range $i, $v := .xs}}{{$i}}={{$v}};{{end}}", data),
    "0=a;1=b;",
  )
}

///|
test "range else on an empty list" {
  let data = dict([("xs", List([]))])
  assert_eq(render("{{range .xs}}x{{else}}empty{{end}}", data), "empty")
}

///|
test "range over a dict iterates sorted keys" {
  let data = dict([
    ("m", dict([("b", Int(2L)), ("a", Int(1L)), ("c", Int(3L))])),
  ])
  assert_eq(
    render("{{range $k, $v := .m}}{{$k}}:{{$v}} {{end}}", data),
    "a:1 b:2 c:3 ",
  )
}

///|
test "with sets dot when truthy" {
  let data = dict([("user", dict([("name", Str("leo"))]))])
  assert_eq(render("{{with .user}}{{.name}}{{end}}", data), "leo")
  assert_eq(
    render("{{with .absent}}{{.name}}{{else}}none{{end}}", data),
    "none",
  )
}

///|
test "variable assignment" {
  let data = dict([("name", Str("world"))])
  assert_eq(render("{{$x := upper .name}}{{$x}}-{{$x}}", data), "WORLD-WORLD")
}

///|
test "pipelines feed the previous result as the last argument" {
  let data = dict([("name", Str("goctl"))])
  assert_eq(render("{{.name | upper}}", data), "GOCTL")
  assert_eq(render("{{upper .name}}", data), "GOCTL")
  assert_eq(render("{{.name | title}}", data), "Goctl")
  assert_eq(render("{{.name | trimPrefix \"go\" | upper}}", data), "CTL")
}

///|
test "string helper functions" {
  let empty = dict([])
  assert_eq(render("{{lower \"ABC\"}}", empty), "abc")
  assert_eq(render("{{trim \"  hi  \"}}", empty), "hi")
  assert_eq(render("{{replace \"a\" \"X\" \"banana\"}}", empty), "bXnXnX")
  assert_eq(render("{{hasPrefix \"foo\" \"foobar\"}}", empty), "true")
  assert_eq(render("{{hasSuffix \"bar\" \"foobar\"}}", empty), "true")
  assert_eq(render("{{contains \"oob\" \"foobar\"}}", empty), "true")
}

///|
test "comparison and logic functions" {
  let empty = dict([])
  assert_eq(render("{{if and (gt 3 1) (lt 2 5)}}Y{{end}}", empty), "Y")
  assert_eq(render("{{if or false true}}Y{{end}}", empty), "Y")
  assert_eq(render("{{if not false}}Y{{end}}", empty), "Y")
  assert_eq(render("{{eq 1 2 1}}", empty), "true")
  assert_eq(render("{{ne 1 2}}", empty), "true")
  assert_eq(render("{{ge 3 3}}", empty), "true")
}

///|
test "len and index and default" {
  let data = dict([("xs", List([Str("a"), Str("b"), Str("c")]))])
  assert_eq(render("{{len .xs}}", data), "3")
  assert_eq(render("{{index .xs 1}}", data), "b")
  assert_eq(render("{{default \"fallback\" \"\"}}", dict([])), "fallback")
  assert_eq(render("{{default \"fallback\" \"real\"}}", dict([])), "real")
}

///|
test "parenthesised sub-pipeline" {
  let data = dict([("xs", List([Str("a"), Str("b")]))])
  assert_eq(render("{{if eq (len .xs) 2}}two{{end}}", data), "two")
}

///|
test "printf formats arguments" {
  let data = dict([("k", Str("age")), ("v", Int(30L))])
  assert_eq(render("{{printf \"%s=%d\" .k .v}}", data), "age=30")
  assert_eq(render("{{printf \"%q\" \"hi\"}}", dict([])), "\"hi\"")
}

///|
test "whitespace-trim markers" {
  // Without trim the newline/indent between actions is preserved.
  let data = dict([("x", Str("v"))])
  assert_eq(
    render(
      (
        #|{{- if .x -}}
        #|  {{.x}}
        #|{{- end -}}
      ),
      data,
    ),
    "v",
  )
}

///|
test "comments are dropped" {
  assert_eq(render("a{{/* note */}}b", dict([])), "ab")
}

///|
test "raw string literal preserves backslashes" {
  assert_eq(render("{{print `a\\nb`}}", dict([])), "a\\nb")
}

///|
test "custom function registration" {
  let t = Template::new().func("shout", xs => {
    Str(to_output(arg_at(xs, 0, "shout")).to_upper() + "!")
  })
  let out = t.parse("{{shout .name}}").render(dict([("name", Str("hey"))]))
  assert_eq(out, "HEY!")
}

///|
test "parse error on unterminated action" {
  try render("{{ .x ", dict([])) |> ignore catch {
    ParseError(_) => ()
    _ => fail("expected a ParseError")
  } noraise {
    _ => fail("expected a parse error but render succeeded")
  }
}

///|
test "exec error on undefined function" {
  try render("{{nope .x}}", dict([])) |> ignore catch {
    ExecError(_) => ()
    _ => fail("expected an ExecError")
  } noraise {
    _ => fail("expected an exec error but render succeeded")
  }
}
