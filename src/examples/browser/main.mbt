// A browser-facing shell around the generator: one spec string in, one JSON
// document out. Everything crossing the boundary is a string, so the page needs to
// know nothing about MoonBit values — and nothing about how the generator works.

///|
/// One finding as a JSON object, so the page can colour it without parsing text.
fn diagnostic_json(d : @api.Diagnostic) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["severity"] = ToJson::to_json(
    match d.severity {
      @api.Error => "error"
      @api.Warning => "warning"
    },
  )
  fields["rule"] = ToJson::to_json(d.rule)
  fields["at"] = ToJson::to_json(d.at)
  fields["message"] = ToJson::to_json(d.message)
  ToJson::to_json(fields)
}

///|
/// The answer for a spec that will not parse: the line it stopped on, and nothing
/// else, since nothing else can be trusted.
fn refused(why : String) -> String {
  let fields : Map[String, Json] = Map([])
  fields["ok"] = ToJson::to_json(false)
  fields["error"] = ToJson::to_json(why)
  @json.dumps(ToJson::to_json(fields))
}

///|
/// The answer for a spec that parsed: the service, its routes, the generated
/// service code, the OpenAPI document, and the findings the validator reports.
fn built(spec : @api.Spec, code : String, openapi : String) -> String {
  let routes : Array[Json] = []
  for r in spec.routes {
    let route : Map[String, Json] = Map([])
    route["verb"] = ToJson::to_json(r.verb)
    route["path"] = ToJson::to_json(r.path)
    route["handler"] = ToJson::to_json(r.handler)
    route["summary"] = ToJson::to_json(r.summary)
    routes.push(ToJson::to_json(route))
  }
  let findings : Array[Json] = []
  for d in @moonctl.validate(spec) {
    findings.push(diagnostic_json(d))
  }
  let fields : Map[String, Json] = Map([])
  fields["ok"] = ToJson::to_json(true)
  fields["service"] = ToJson::to_json(spec.service)
  fields["routes"] = ToJson::to_json(routes)
  fields["code"] = ToJson::to_json(code)
  fields["openapi"] = ToJson::to_json(openapi)
  fields["findings"] = ToJson::to_json(findings)
  @json.dumps(ToJson::to_json(fields))
}

///|
/// Compile one `.api` spec: `ok: true` with the generated service, the three-version
/// OpenAPI document and the findings, or `ok: false` with the line the parser
/// stopped on.
pub fn compile(spec : String) -> String {
  let parsed : Result[@api.Spec, @api.Refused] = Ok(@moonctl.parse(spec)) catch {
    e => Err(e)
  }
  let spec = match parsed {
    Ok(spec) => spec
    Err(e) =>
      return refused(
        match e {
          @api.Syntax(line~, msg~) => "line " + line.to_string() + ": " + msg
          @api.Missing(file~, path~) => "cannot read " + path + " from " + file
        },
      )
  }
  let code = @moonctl.generate(spec) catch {
    @template.ParseError(why) => return refused("template parse error: " + why)
    @template.ExecError(why) => return refused("template exec error: " + why)
  }
  built(spec, code, @moonctl.generate_doc(spec))
}
