// `mctl api doc`: the reference a team reads, as Markdown (goctl's `api doc`).
//
// The OpenAPI document in `doc.mbt` is for a machine — a generator, a gateway, a
// test suite. This one is for the person who has to call the service: a table of
// routes, then one table per type saying where each field is bound and what the
// spec constrains it to. Markdown rather than HTML so it can be committed beside
// the spec and diffed when the spec changes.

///|
/// One table cell: the text with the `|` that would break a row escaped, and the
/// newlines a multi-line value carries folded into spaces.
fn cell(s : String) -> String {
  let mut out = ""
  let mut start = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '|' || c == '\n' || c == '\r' {
      out = out + s[start:i].to_owned() + (if c == '|' { "\\|" } else { " " })
      start = i + 1
    }
  }
  @text.trim(out + s[start:].to_owned())
}

///|
/// Where a field is bound, as a word a reader recognises.
fn bind_word(f : @api.Field) -> String {
  match f.bind() {
    @api.Body => "body"
    @api.Query => "query"
    @api.Path => "path"
    @api.Header => "header"
  }
}

///|
/// The constraints a tag carries — `default=`, `options=`, `range=`, `optional` —
/// as one line, or an empty string when the tag carries none.
fn constraints(f : @api.Field) -> String {
  let parts : Array[String] = []
  // `options=free|pro` is one constraint with two permitted values, so it reads as
  // one phrase — "one of `free`, `pro`" — rather than the phrase twice.
  let allowed = f.options()
  if allowed.length() > 0 {
    let mut listed = ""
    for i = 0; i < allowed.length(); i = i + 1 {
      if i > 0 {
        listed = listed + ", "
      }
      listed = listed + "`" + allowed[i] + "`"
    }
    parts.push("one of " + listed)
  }
  match f.default_() {
    Some(v) => parts.push("default `" + v + "`")
    None => ()
  }
  match f.range() {
    Some(r) => {
      let lo = if r.lo == "" { "" } else { r.lo }
      let hi = if r.hi == "" { "" } else { r.hi }
      parts.push(
        "range " +
        (if r.lo_inc { "[" } else { "(" }) +
        lo +
        ".." +
        hi +
        (if r.hi_inc { "]" } else { ")" }),
      )
    }
    None => ()
  }
  if f.optional() {
    parts.push("optional")
  }
  parts.join(", ")
}

///|
/// The routes of a spec as one table, in spec order.
fn routes_table(spec : @api.Spec) -> Array[String] {
  let out : Array[String] = []
  out.push("| Method | Path | Handler | Request | Response | Description |")
  out.push("| --- | --- | --- | --- | --- | --- |")
  for r in spec.routes {
    out.push(
      "| " +
      cell(r.verb.to_upper()) +
      " | `" +
      cell(r.path) +
      "` | `" +
      cell(r.handler) +
      "` | " +
      (if r.req == "" { "—" } else { "`" + cell(r.req) + "`" }) +
      " | " +
      (if r.resp == "" { "—" } else { "`" + cell(r.resp) + "`" }) +
      " | " +
      cell(if r.summary == "" { "—" } else { r.summary }) +
      " |",
    )
  }
  out
}

///|
/// One type block as a table: the wire name, the MoonBit type, where the value is
/// bound from, whether the caller has to send it, and what the tag constrains.
fn type_table(t : @api.TypeDef, types : Array[@api.TypeDef]) -> Array[String] {
  let out : Array[String] = []
  out.push("### " + t.name)
  out.push("")
  let fields = @api.flat_fields(t, types)
  if fields.length() == 0 {
    out.push("_The block declares no field._")
    out.push("")
    return out
  }
  out.push("| Field | Type | In | Required | Constraints |")
  out.push("| --- | --- | --- | --- | --- |")
  for f in fields {
    out.push(
      "| `" +
      cell(f.json_name()) +
      "` | `" +
      cell(f.type_) +
      "` | " +
      bind_word(f) +
      " | " +
      (if f.optional() { "no" } else { "yes" }) +
      " | " +
      cell(constraints(f)) +
      " |",
    )
  }
  out.push("")
  out
}

///|
/// The whole reference: the service, a route table, then a table per type. `title`
/// replaces the service name in the heading for a reader who wants the document to
/// say what the service is for.
pub fn generate_markdown(spec : @api.Spec, title? : String) -> String {
  let out : Array[String] = []
  let heading = match title {
    Some(t) => t
    None => if spec.service == "" { "API" } else { spec.service }
  }
  out.push("# " + heading)
  out.push("")
  let summary = "A MoonAPI service with " +
    spec.routes.length().to_string() +
    " route(s) and " +
    spec.types.length().to_string() +
    " type(s)."
  out.push(summary)
  out.push("")
  if spec.info.length() > 0 {
    out.push("| Key | Value |")
    out.push("| --- | --- |")
    for kv in spec.info {
      out.push("| " + cell(kv.0) + " | " + cell(kv.1) + " |")
    }
    out.push("")
  }
  out.push("## Routes")
  out.push("")
  if spec.routes.length() == 0 {
    out.push("_The service declares no route._")
  } else {
    for line in routes_table(spec) {
      out.push(line)
    }
    if spec.groups.length() > 0 {
      out.push("")
      out.push("### Groups")
      out.push("")
      out.push("| Group | Prefix | JWT | Middleware | Max body | Timeout |")
      out.push("| --- | --- | --- | --- | --- | --- |")
      for g in spec.groups {
        out.push(
          "| `" +
          cell(g.name) +
          "` | `" +
          cell(g.prefix) +
          "` | " +
          (if g.jwt == "" { "—" } else { "`" + cell(g.jwt) + "`" }) +
          " | " +
          (if g.middleware.length() == 0 {
            "—"
          } else {
            g.middleware.map(fn(m) { "`" + m + "`" }).join(", ")
          }) +
          " | " +
          (if g.max_bytes == 0L { "—" } else { g.max_bytes.to_string() }) +
          " | " +
          (if g.timeout == "" { "—" } else { "`" + cell(g.timeout) + "`" }) +
          " |",
        )
      }
    }
  }
  out.push("")
  out.push("## Types")
  out.push("")
  if spec.types.length() == 0 {
    out.push("_The spec declares no type._")
    out.push("")
  } else {
    for t in spec.types {
      for line in type_table(t, spec.types) {
        out.push(line)
      }
    }
  }
  out.push("---")
  out.push("")
  out.push("Generated by `mctl api doc`. Edit the `.api` spec, not this file.")
  @text.join_lines(out)
}

///|
/// The file name a Markdown reference lands in: `greet` → `greet_api.md`.
pub fn markdown_file_name(service : String) -> String {
  (if service == "" { "api" } else { @text.to_snake(service) }) + "_api.md"
}
