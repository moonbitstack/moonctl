// A runtime template engine — moonctl's faithful equivalent of goctl's
// `text/template`. It parses a template into a node tree once, then renders it
// against a dynamic `Value` (MoonBit has no reflection, so template data is an
// explicit tagged value the way `encoding/json` models it). Supports `{{.Field}}`
// interpolation, `{{if}}/{{else}}/{{range}}/{{with}}/{{end}}`, `$variable`
// assignment, `|` pipelines, parenthesised sub-pipelines, `{{- -}}` whitespace
// trimming, `{{/* comments */}}`, and a library of pipeline functions. Pure and
// all-backend.

///|
/// One `@server` group as template data: `{name, prefix, jwt, middleware,
/// maxBytes, timeout, signature}` plus every annotation mctl does not name itself.
fn group_to_value(g : @api.Group) -> @template.Value {
  let middleware : Array[@template.Value] = []
  for m in g.middleware {
    middleware.push(Str(m))
  }
  let fields : Array[(String, @template.Value)] = [
    ("name", Str(g.name)),
    ("prefix", Str(g.prefix)),
    ("jwt", Str(g.jwt)),
    ("middleware", List(middleware)),
    ("maxBytes", Int(g.max_bytes)),
    ("timeout", Str(g.timeout)),
    ("signature", Bool(g.signature)),
  ]
  for kv in g.extra {
    fields.push((kv.0, Str(kv.1)))
  }
  Dict(Map(fields))
}

///|
/// Expose a parsed `.api` `Spec` as template `Value` data: a `Dict` with
/// `service` (string), `routes` (list of `{verb, path, handler, summary,
/// hasSummary, group, hasGroup}`), `types` (list of `{name, fields:[{name,
/// type}]}`), `groups` (list of the `@server` blocks) and `hasTypes` (bool). This
/// is what the template-driven generator ranges over.
pub fn spec_to_value(spec : @api.Spec) -> @template.Value {
  let routes : Array[@template.Value] = []
  for r in spec.routes {
    let name = match r.group {
      Some(g) => g.name
      None => ""
    }
    routes.push(
      Dict(
        Map([
          ("verb", @template.Str(r.verb)),
          ("path", @template.Str(r.path)),
          ("handler", @template.Str(r.handler)),
          ("summary", @template.Str(r.summary)),
          ("hasSummary", @template.Bool(r.summary != "")),
          ("group", @template.Str(name)),
          ("hasGroup", @template.Bool(name != "")),
        ]),
      ),
    )
  }
  let groups : Array[@template.Value] = []
  for g in spec.groups {
    groups.push(group_to_value(g))
  }
  let types : Array[@template.Value] = []
  for t in spec.types {
    let fields : Array[@template.Value] = []
    for f in t.fields {
      fields.push(
        Dict(
          Map([
            ("name", @template.Str(f.name)),
            ("type", @template.Str(f.type_)),
          ]),
        ),
      )
    }
    types.push(
      Dict(
        Map([
          ("name", @template.Str(t.name)),
          ("fields", @template.List(fields)),
        ]),
      ),
    )
  }
  Dict(
    Map([
      ("service", @template.Str(spec.service)),
      ("routes", @template.List(routes)),
      ("types", @template.List(types)),
      ("groups", @template.List(groups)),
      ("hasTypes", @template.Bool(spec.types.length() != 0)),
    ]),
  )
}

///|
/// Generate code from a `Spec` with a caller-supplied template instead of the
/// built-in generator — the runtime-template path goctl exposes for custom
/// scaffolds. Equivalent to `render(template_source, spec_to_value(spec))`.
pub fn generate_with(
  spec : @api.Spec,
  template_source : String,
) -> String raise @template.TemplateError {
  @template.render(template_source, spec_to_value(spec))
}
