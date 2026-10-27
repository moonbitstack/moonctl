///|
test "generate_with drives codegen from a custom template" {
  let spec = @api.parse(
    (
      #|service greet {
      #|  get /ping ping "health check"
      #|  post /users create_user
      #|}
    ),
  )
  let tmpl =
    #|// service: {{.service}}
    #|{{range .routes}}{{.verb}} {{.path}} -> {{.handler}}
    #|{{end}}
  let out = generate_with(spec, tmpl)
  assert_eq(
    out,
    (
      #|// service: greet
      #|get /ping -> ping
      #|post /users -> create_user
      #|
    ),
  )
}

///|
test "generate_with renders type blocks" {
  let spec = @api.parse(
    (
      #|type User {
      #|  id:   int64
      #|  name: string
      #|}
      #|service greet {
      #|  get /users/:id get_user
      #|}
    ),
  )
  let tmpl =
    #|{{range .types}}struct {{.name}} { {{range .fields}}{{.name}}:{{.type}} {{end}}}{{end}}
  assert_eq(generate_with(spec, tmpl), "struct User { id:Int64 name:String }")
}
