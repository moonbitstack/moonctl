///|
/// The runtime template engine — moonctl's faithful `text/template` (goctl drives
/// codegen through Go's). MoonBit has no reflection, so template data is an
/// explicit tagged `Value`. This walks `render` over hand-built data
/// (`{{.field}}` interpolation, `{{range}}`, `{{if}}`, `|` pipelines, the built-in
/// function library, `printf`), a reusable `Template` with a caller-registered
/// `func`, and the codegen seam: `spec_to_value` exposes a parsed `.api` `Spec` as
/// `Value`, and `generate_with` / `generate(spec, template=...)` scaffold from a
/// caller's own template instead of the built-in generator.
///
///     moon run src/examples/09-template
#coverage.skip
fn dict(entries : Array[(String, @moonctl.Value)]) -> @moonctl.Value {
  Dict(Map(entries))
}

///|
#coverage.skip
fn main {
  let data = dict([
    ("service", Str("greet")),
    ("count", Int(233L)),
    (
      "routes",
      List([
        dict([("verb", Str("get")), ("path", Str("/ping"))]),
        dict([("verb", Str("post")), ("path", Str("/users"))]),
      ]),
    ),
  ])
  try {
    println("==== render over hand-built Value data ====\n")
    println(@moonctl.render("service = {{.service}} ({{.count}} routes)", data))
    println(
      @moonctl.render(
        "{{range .routes}}{{.verb | upper}} {{.path}}\n{{end}}", data,
      ),
    )
    println(@moonctl.render("{{printf \"%s -> %d\" .service .count}}", data))

    // A reusable Template with a caller-registered pipeline function; the piped
    // value arrives as the last argument, so `bang` chains under `|`.
    let bang = @moonctl.Template::new().func("bang", xs => {
      match xs[xs.length() - 1] {
        Str(s) => Str(s + "!")
        other => other
      }
    })
    println("\n==== Template::func — a custom pipeline function ====\n")
    println(bang.parse("{{.service | bang | bang}}").render(data))

    // The codegen seam: a parsed spec exposed as template data, then scaffolded
    // through a caller-supplied template two equivalent ways.
    let source =
      #|type User {
      #|  id:   int64
      #|  name: string
      #|}
      #|
      #|service greet {
      #|  get  /ping       ping        "health check"
      #|  post /users      create_user "create a user"
      #|}
    let spec = @moonctl.parse(source)
    let tmpl =
      #|// service: {{.service}}
      #|{{range .routes}}route {{.verb}} {{.path}} -> {{.handler}}{{if .hasSummary}} ({{.summary}}){{end}}
      #|{{end}}{{range .types}}type {{.name}}: {{range .fields}}{{.name}}:{{.type}} {{end}}
      #|{{end}}
    println("\n==== render(tmpl, spec_to_value(spec)) ====\n")
    println(@moonctl.render(tmpl, @moonctl.spec_to_value(spec)))
    let via_with = @moonctl.generate_with(spec, tmpl)
    let via_param = @moonctl.generate(spec, template=tmpl)
    println("generate_with == generate(template=): \{via_with == via_param}")
  } catch {
    _ => println("template render failed")
  }
}
