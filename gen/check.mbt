// What a tag's constraints turn into. `optional`, `default=`, `options=` and
// `range=` describe a value the service has not seen yet, so half of each lands in
// the OpenAPI document (`required`, `default`, `enum`, `minimum`/`maximum`) and the
// other half has to be code the service runs: `with_defaults` fills in what the
// request left out, `check` refuses what it got wrong. Both are emitted beside the
// struct they belong to, so `internal/types` carries the rules the spec declared
// instead of leaving them in a document nobody executes.

///|
/// A MoonBit literal of type `type_` spelling `raw`, or `None` when the type has no
/// literal form a generated comparison could use (an `Array`, a `Map`, a nested
/// message).
fn lit(type_ : String, raw : String) -> String? {
  match type_ {
    "String" => Some(@text.quote(raw))
    "Bool" => if raw == "true" || raw == "false" { Some(raw) } else { None }
    "Int" => Some(raw)
    "Int64" => Some(raw + "L")
    "UInt" => Some(raw + "U")
    "UInt64" => Some(raw + "UL")
    "Double" =>
      Some(if @api.index_of(raw, '.', 0) < 0 { raw + ".0" } else { raw })
    "Float" =>
      Some(
        "(" +
        (if @api.index_of(raw, '.', 0) < 0 { raw + ".0" } else { raw }) +
        " : Float)",
      )
    _ => None
  }
}

///|
/// `raw` as a JSON number, or as a string when it does not read as one — a tag
/// option is text until something asks it to be a number.
pub fn number_json(raw : String) -> Json {
  let d = @string.parse_double(raw) catch { _ => return Json(raw) }
  Json(d)
}

///|
/// Whether `type_` is one a `range=` can bound.
fn is_numeric(type_ : String) -> Bool {
  match type_ {
    "Int" | "Int64" | "UInt" | "UInt64" | "Double" | "Float" => true
    _ => false
  }
}

///|
/// The value a member of type `type_` decodes to when the request left it out —
/// what a `default=` replaces. `None` for a type with no single such value.
fn zero_lit(type_ : String) -> String? {
  match type_ {
    "String" => Some("\"\"")
    "Bool" => Some("false")
    _ => if is_numeric(type_) { lit(type_, "0") } else { None }
  }
}

///|
/// The `if …` line refusing a value outside a field's `range=`, or "" when the
/// field's type has no bounds to compare against. An open end contributes nothing,
/// so `range=[1:]` only refuses what is below 1.
fn range_check(f : @api.Field, r : @api.Range) -> String {
  if is_numeric(f.type_) == false {
    return ""
  }
  let tests : Array[String] = []
  let field = "self." + f.mbt_name()
  match lit(f.type_, r.lo) {
    Some(v) =>
      if r.lo != "" {
        tests.push(field + (if r.lo_inc { " < " } else { " <= " }) + v)
      }
    None => ()
  }
  match lit(f.type_, r.hi) {
    Some(v) =>
      if r.hi != "" {
        tests.push(field + (if r.hi_inc { " > " } else { " >= " }) + v)
      }
    None => ()
  }
  if tests.length() == 0 {
    return ""
  }
  let mut cond = ""
  for t in tests {
    cond = if cond == "" { t } else { cond + " || " + t }
  }
  let span = (if r.lo_inc { "[" } else { "(" }) +
    r.lo +
    ":" +
    r.hi +
    (if r.hi_inc { "]" } else { ")" })
  "  if " +
  cond +
  " {\n    return Some(" +
  @text.quote(f.json_name() + " is out of range " + span) +
  ")\n  }\n"
}

///|
/// The `if …` line refusing a value the field's `options=` does not list, or "" when
/// the field's type has no literal to compare against.
fn options_check(f : @api.Field, allowed : Array[String]) -> String {
  let tests : Array[String] = []
  for one in allowed {
    match lit(f.type_, one) {
      Some(v) => tests.push("self." + f.mbt_name() + " != " + v)
      None => return ""
    }
  }
  if tests.length() == 0 {
    return ""
  }
  let mut cond = ""
  let mut listed = ""
  for t in tests {
    cond = if cond == "" { t } else { cond + " && " + t }
  }
  for one in allowed {
    listed = if listed == "" { one } else { listed + "|" + one }
  }
  "  if " +
  cond +
  " {\n    return Some(" +
  @text.quote(f.json_name() + " is not one of " + listed) +
  ")\n  }\n"
}

///|
/// The checks `fields` ask for, in declaration order: a required string that came
/// through empty, then any `options=` and `range=` they declared.
fn check_body(fields : Array[@api.Field]) -> String {
  let mut out = ""
  for f in fields {
    if f.optional() == false && f.type_ == "String" {
      out = out +
        "  if self." +
        f.mbt_name() +
        " == \"\" {\n    return Some(" +
        @text.quote(f.json_name() + " is required") +
        ")\n  }\n"
    }
    let allowed = f.options()
    if allowed.length() > 0 {
      out = out + options_check(f, allowed)
    }
    match f.range() {
      Some(r) => out = out + range_check(f, r)
      None => ()
    }
  }
  out
}

///|
/// The `default=` substitutions `fields` ask for, as `field: if … ` pairs.
fn default_pairs(fields : Array[@api.Field]) -> Array[String] {
  let out : Array[String] = []
  for f in fields {
    let raw = match f.default_() {
      Some(v) => v
      None => continue
    }
    let value = match lit(f.type_, raw) {
      Some(v) => v
      None => continue
    }
    let zero = match zero_lit(f.type_) {
      Some(z) => z
      None => continue
    }
    let name = f.mbt_name()
    out.push(
      "    " +
      name +
      ": if self." +
      name +
      " == " +
      zero +
      " { " +
      value +
      " } else { self." +
      name +
      " },",
    )
  }
  out
}

///|
/// The constraint code a `type` block's tags ask for, to sit beside the struct:
/// `with_defaults` when any field declared a `default=`, and `check` when any
/// declared `options=`, a `range=`, or is a required string. A block whose tags ask
/// for neither gets neither, so a spec that constrains nothing generates nothing.
fn render_checks(name : String, fields : Array[@api.Field]) -> String {
  let mut out = ""
  let pairs = default_pairs(fields)
  if pairs.length() > 0 {
    out = out +
      "///|\n/// `" +
      name +
      "` with every `default=` the spec declared filled in where the value is still\n/// the one an absent member decodes to. Run it before `check`, which is what makes\n/// a defaulted field pass the constraints its tag also declared.\npub fn " +
      name +
      "::with_defaults(self : " +
      name +
      ") -> " +
      name +
      " {\n  {\n    ..self,\n" +
      @text.join_lines(pairs) +
      "\n  }\n}\n\n"
  }
  let body = check_body(fields)
  if body != "" {
    out = out +
      "///|\n/// Check `" +
      name +
      "` against the constraints its `.api` tags declared: a required string that\n/// came through empty, an `options=` value not on the list, a number outside its\n/// `range=`. The first field that fails, or `None` when every one holds.\npub fn " +
      name +
      "::check(self : " +
      name +
      ") -> String? {\n" +
      body +
      "  None\n}\n\n"
  }
  out
}
