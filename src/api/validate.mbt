// `api validate`: the checks a `.api` spec has to pass before it is worth
// generating from (← goctl's `goctl api validate`). The parser already refuses a
// line it cannot read; what is left are the mistakes a parser cannot see — a route
// pointing at a type nobody declared, two handlers under one name, a `:id` segment
// with no field to fill it. Each finding names the rule that caught it, so a
// toolchain can turn one class of finding off without turning the rest off.

///|
/// How bad a finding is: `Error` means the generated code would not compile or
/// would not match the spec, `Warning` means it would compile but probably is not
/// what the author meant.
pub(all) enum Severity {
  Error
  Warning
} derive(Eq)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
/// One finding of `validate`: how bad it is, the `rule` that produced it, the
/// `at` — the route, type or field it is about — and a sentence saying what is
/// wrong.
pub(all) struct Diagnostic {
  severity : Severity
  rule : String
  at : String
  message : String
}

///|
pub impl Show for Diagnostic with fn output(self, logger) {
  logger.write_string(
    match self.severity {
      Error => "error"
      Warning => "warning"
    },
  )
  logger.write_string(" [" + self.rule + "] " + self.at + ": " + self.message)
}

///|
/// `to_string` is how a report line is built, so it is spelled out rather than left
/// to the implicit promotion the compiler now warns about.
pub extend Diagnostic with Show::{to_string, output}

///|
/// Whether any finding is an `Error` — what makes `mctl api validate` exit non-zero.
pub fn has_errors(diagnostics : Array[Diagnostic]) -> Bool {
  for d in diagnostics {
    if d.severity == Error {
      return true
    }
  }
  false
}

///|
/// The names MoonBit will not take as an identifier. A handler named one of these
/// compiles into a function whose name the language rejects, so it is an error and
/// not a warning.
fn is_keyword(name : String) -> Bool {
  match name {
    "as"
    | "async"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "deriving"
    | "else"
    | "enum"
    | "extern"
    | "false"
    | "fn"
    | "for"
    | "guard"
    | "if"
    | "impl"
    | "in"
    | "init"
    | "is"
    | "let"
    | "main"
    | "match"
    | "mut"
    | "not"
    | "open"
    | "panic"
    | "priv"
    | "pub"
    | "raise"
    | "return"
    | "self"
    | "struct"
    | "test"
    | "trait"
    | "true"
    | "try"
    | "type"
    | "while"
    | "with" => true
    _ => false
  }
}

///|
/// The scalar spellings a field type may end at without naming another `type`
/// block. Anything else is a reference, and `validate` insists it is declared.
fn is_scalar(t : String) -> Bool {
  match t {
    "String"
    | "Bool"
    | "Int"
    | "Int32"
    | "Int64"
    | "UInt"
    | "UInt32"
    | "UInt64"
    | "Byte"
    | "Bytes"
    | "Double"
    | "Float"
    | "Unit"
    | "Json" => true
    _ => false
  }
}

///|
/// The index of the `", "` between a `Map[K, V]`'s two halves, or `-1`.
fn top_comma(s : String) -> Int32 {
  let mut depth = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '[' {
      depth = depth + 1
    } else if c == ']' {
      depth = depth - 1
    } else if c == ',' && depth == 0 {
      return i
    }
  }
  -1
}

///|
/// Collect the `type` blocks a MoonBit type spelling refers to: `User` names one,
/// `Array[User]` and `Map[String, User]` name the same one, `String` names none.
fn collect_refs(t : String, out : Array[String]) -> Unit {
  let s = @text.trim(t)
  if s == "" {
    return
  }
  if @text.ends_with(s, "?") {
    collect_refs(s[0:s.length() - 1].to_owned(), out)
    return
  }
  if @text.starts_with(s, "Array[") && @text.ends_with(s, "]") {
    collect_refs(s[6:s.length() - 1].to_owned(), out)
    return
  }
  if @text.starts_with(s, "Map[") && @text.ends_with(s, "]") {
    let body = s[4:s.length() - 1].to_owned()
    let comma = top_comma(body)
    if comma >= 0 {
      collect_refs(body[0:comma].to_owned(), out)
      collect_refs(body[comma + 1:].to_owned(), out)
    }
    return
  }
  let mapped = map_type(s)
  if is_scalar(mapped) == false {
    out.push(mapped)
  }
}

///|
/// Whether `types` declares `name`.
fn declares(types : Array[TypeDef], name : String) -> Bool {
  for t in types {
    if t.name == name {
      return true
    }
  }
  false
}

///|
/// The `:name` segments of a route path, in order.
fn path_params(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in @text.path_segments(path) {
    if seg.length() > 0 && seg[0] == ':' {
      out.push(seg[1:].to_owned())
    }
  }
  out
}

///|
/// The fields a route request type carries, resolving an embedded type; empty when
/// the route names no request type or names one the spec does not declare.
fn request_fields(spec : Spec, route : Route) -> Array[Field] {
  if route.req == "" {
    return []
  }
  match find_type(spec.types, route.req) {
    None => []
    Some(t) => flat_fields(t, spec.types)
  }
}

///|
/// A finding, built once so every rule reports in the same shape.
fn finding(
  severity : Severity,
  rule : String,
  at : String,
  message : String,
) -> Diagnostic {
  { severity, rule, at, message, }
}

///|
/// Check a parsed spec: the routes, the types and the places one names the other.
/// Findings come in spec order — routes first, then types — so a report reads the
/// way the file does.
pub fn validate(spec : Spec) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  let types = spec.types
  // routes: one handler per name, one handler per verb + path
  let handlers : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  for r in spec.routes {
    let at = r.verb + " " + r.path
    if handlers.contains(r.handler) {
      out.push(
        finding(
          Error,
          "duplicate-handler",
          at,
          "handler \"" + r.handler + "\" is declared by more than one route",
        ),
      )
    }
    handlers[r.handler] = true
    let key = r.verb + " " + r.path
    if paths.contains(key) {
      out.push(
        finding(
          Error,
          "duplicate-route",
          at,
          "the same verb and path is declared twice",
        ),
      )
    }
    paths[key] = true
    if is_keyword(r.handler) {
      out.push(
        finding(
          Error,
          "reserved-handler",
          at,
          "\"" +
          r.handler +
          "\" is a MoonBit keyword, so the generated function cannot carry it",
        ),
      )
    }
    if r.req != "" && declares(types, r.req) == false {
      out.push(
        finding(
          Error,
          "unknown-type",
          at,
          "request type \"" + r.req + "\" is not declared",
        ),
      )
    }
    if r.resp != "" && declares(types, r.resp) == false {
      out.push(
        finding(
          Error,
          "unknown-type",
          at,
          "response type \"" + r.resp + "\" is not declared",
        ),
      )
    }
    let fields = request_fields(spec, r)
    for param in path_params(r.path) {
      let mut bound = false
      for f in fields {
        if f.json_name() == param || f.mbt_name() == param {
          bound = true
        }
      }
      if r.req != "" && declares(types, r.req) && bound == false {
        out.push(
          finding(
            Warning,
            "path-param",
            at,
            "`:" +
            param +
            "` has no field named \"" +
            param +
            "\" in " +
            r.req +
            ", so nothing fills it",
          ),
        )
      }
    }
  }
  if spec.service != "" && spec.routes.length() == 0 {
    out.push(
      finding(
        Warning,
        "empty-service",
        "service " + spec.service,
        "the service declares no route",
      ),
    )
  }
  let used_groups : Map[String, Bool] = Map([])
  for r in spec.routes {
    match r.group {
      Some(g) => used_groups[g.name] = true
      None => ()
    }
  }
  for g in spec.groups {
    if used_groups.contains(g.name) == false {
      out.push(
        finding(
          Warning,
          "unused-group",
          "@server(" + g.name + ")",
          "the group annotates no route",
        ),
      )
    }
  }
  // types: one declaration per name, one field per name, every reference declared
  let declared : Map[String, Bool] = Map([])
  for t in types {
    if declared.contains(t.name) {
      out.push(
        finding(
          Error,
          "duplicate-type",
          "type " + t.name,
          "\"" + t.name + "\" is declared more than once",
        ),
      )
    }
    declared[t.name] = true
  }
  for t in types {
    // A bare `Base` line inlines another block: it names that block the same way a
    // field type does, so an undeclared embed is the same `unknown-type` finding.
    for e in t.embeds {
      if declared.contains(e) == false {
        out.push(
          finding(
            Error,
            "unknown-type",
            "type " + t.name,
            "embedded type \"" + e + "\" is not declared",
          ),
        )
      }
    }
    let fields = flat_fields(t, types)
    if fields.length() == 0 {
      out.push(
        finding(
          Warning,
          "empty-type",
          "type " + t.name,
          "the block declares no field",
        ),
      )
    }
    let names : Map[String, Bool] = Map([])
    for f in fields {
      let at = "type " + t.name + "." + f.name
      if names.contains(f.name) {
        out.push(
          finding(
            Error,
            "duplicate-field",
            at,
            "the field is declared twice in the same block",
          ),
        )
      }
      names[f.name] = true
      let refs : Array[String] = []
      collect_refs(f.type_, refs)
      for r in refs {
        if declared.contains(r) == false {
          out.push(
            finding(
              Error,
              "unknown-type",
              at,
              "field type \"" + r + "\" is not declared",
            ),
          )
        }
      }
    }
  }
  for t in types {
    let mut used = false
    for r in spec.routes {
      if r.req == t.name || r.resp == t.name {
        used = true
      }
    }
    for other in types {
      if other.name == t.name {
        continue
      }
      for e in other.embeds {
        if e == t.name {
          used = true
        }
      }
      for f in flat_fields(other, types) {
        let refs : Array[String] = []
        collect_refs(f.type_, refs)
        for r in refs {
          if r == t.name {
            used = true
          }
        }
      }
    }
    if used == false {
      out.push(
        finding(
          Warning,
          "unused-type",
          "type " + t.name,
          "no route and no other type refers to it",
        ),
      )
    }
  }
  out
}

///|
/// Validate a spec given as source. A spec the parser cannot read is reported as
/// the one finding it is — `syntax`, naming the line — rather than raising, so a
/// caller checks a file the same way whether it is broken or merely wrong.
pub fn validate_source(source : String) -> Array[Diagnostic] {
  let spec = parse(source) catch {
    Syntax(line~, msg~) =>
      return [finding(Error, "syntax", "line " + line.to_string(), msg)]
    Missing(file~, path~) =>
      return [
        finding(Error, "import", file, "cannot read import \"" + path + "\""),
      ]
  }
  validate(spec)
}
