///|
/// A spec with two routes, one of them carrying a request type.
fn dir_spec() -> @api.Spec {
  @api.parse_lenient(
    (
      #|type CreateReq {
      #|  name: string
      #|}
      #|
      #|service greet {
      #|  @handler ping
      #|  get /ping
      #|
      #|  @handler create
      #|  post /items (CreateReq)
      #|}
    ),
  )
}

///|
test "a template library renders both the file's path and its text" {
  let files = [
    TemplateFile::{ path: "{{.service}}.mbt", text: "// {{.service}}\n", },
    TemplateFile::{
      path: "etc/{{.service}}.yaml",
      text: "name: {{.service}}\n",
    },
  ]
  let out = render_template_dir(dir_spec(), files)
  assert_eq(out[0].0, "greet.mbt")
  assert_eq(out[0].1, "// greet\n")
  assert_eq(out[1].0, "etc/greet.yaml")
  assert_eq(out[1].1, "name: greet\n")
}

///|
test "a path with no template in it is left alone" {
  let out = render_template_file(dir_spec(), {
    path: "internal/config/config.mbt",
    text: "port: 12000\n",
  })
  assert_eq(out.0, "internal/config/config.mbt")
  assert_eq(out.1, "port: 12000\n")
}

///|
test "the routes a template ranges over carry their request and reply types" {
  let out = render_template_file(dir_spec(), {
    path: "routes.txt",
    text: (
      #|{{range .routes}}{{.verb}} {{.path}}{{if .hasReq}} ({{.req}}){{end}}{{if .hasResp}} -> {{.resp}}{{end}}
      #|{{end}}
    ),
  })
  assert_eq(out.1, "get /ping\npost /items (CreateReq)\n")
}

///|
test "a template sees the service blocks apart" {
  let spec = @api.parse_lenient(
    (
      #|service alpha {
      #|  get /a a
      #|}
      #|
      #|service beta {
      #|  get /b b
      #|}
    ),
  )
  let out = render_template_file(spec, {
    path: "blocks.txt",
    text: "{{range .services}}{{.name}}:{{range .routes}} {{.}}{{end}}\n{{end}}",
  })
  assert_eq(out.1, "alpha: a\nbeta: b\n")
}
