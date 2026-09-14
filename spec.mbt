///|
fn is_ws(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn trim(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && is_ws(s[a]) {
    a = a + 1
  }
  while b > a && is_ws(s[b - 1]) {
    b = b - 1
  }
  s[a:b].to_owned()
}

///|
fn lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || s[i] == '\n' {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  out
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  let pn = prefix.length()
  if s.length() < pn {
    return false
  }
  for i = 0; i < pn; i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// Index of the first `ch` in `s` at or after `from`, or `-1` if absent.
fn index_of(s : String, ch : UInt16, from : Int) -> Int {
  let n = s.length()
  for i = from; i < n; i = i + 1 {
    if s[i] == ch {
      return i
    }
  }
  -1
}

///|
/// `line` with any trailing `//` comment cut off. A `//` inside a quoted string or
/// a back-tick struct tag is left alone, so a route summary and a `json:"…"` tag
/// survive a commented line.
fn strip_comment(line : String) -> String {
  let n = line.length()
  let mut in_str = false
  let mut in_tag = false
  for i = 0; i < n; i = i + 1 {
    let c = line[i]
    if c == '"' && in_tag == false {
      in_str = in_str == false
    } else if c == '`' && in_str == false {
      in_tag = in_tag == false
    } else if c == '/' &&
      in_str == false &&
      in_tag == false &&
      i + 1 < n &&
      line[i + 1] == '/' {
      return line[0:i].to_owned()
    }
  }
  line
}

///|
/// `s` with one wrapping pair of double quotes removed.
fn unquote(s : String) -> String {
  let n = s.length()
  if n >= 2 && s[0] == '"' && s[n - 1] == '"' {
    s[1:n - 1].to_owned()
  } else {
    s
  }
}

///|
/// `s` without a trailing `{`, so `service greet{` names the service `greet`.
fn drop_brace(s : String) -> String {
  let n = s.length()
  if n > 0 && s[n - 1] == '{' {
    trim(s[0:n - 1].to_owned())
  } else {
    s
  }
}

///|
/// `s` read as a non-negative decimal, or `None` when it is not one.
fn to_i64(s : String) -> Int64? {
  let n = s.length()
  if n == 0 {
    return None
  }
  let mut v : Int64 = 0
  for i = 0; i < n; i = i + 1 {
    if !is_digit(s[i]) {
      return None
    }
    v = v * 10L + (s[i].to_int() - 48).to_int64()
  }
  Some(v)
}

///|
/// A group prefix joined onto a route path: `("/api/v1", "/ping")` → `/api/v1/ping`.
/// Surplus slashes on either side collapse, and an empty (or all-slash) prefix
/// leaves the path alone.
fn join_path(prefix : String, path : String) -> String {
  let mut end = prefix.length()
  while end > 0 && prefix[end - 1] == '/' {
    end = end - 1
  }
  let mut start = 0
  while start < end && prefix[start] == '/' {
    start = start + 1
  }
  if start >= end {
    return path
  }
  let head = "/" + prefix[start:end].to_owned()
  if path == "" || path == "/" {
    head
  } else if path[0] == '/' {
    head + path
  } else {
    head + "/" + path
  }
}

///|
/// Map a `.api` field type onto its MoonBit spelling (← goctl's Go type set):
/// scalars (`string`→`String`, `int`→`Int`, `int64`→`Int64`, …), slices
/// (`[]T`→`Array[T]`), and maps (`map[K]V`→`Map[K, V]`). An unrecognised name is
/// passed through verbatim, so a spec may already reference a MoonBit type or one
/// of its own `type` blocks.
fn map_type(raw : String) -> String {
  let t = trim(raw)
  if starts_with(t, "*") {
    return map_type(t[1:].to_owned()) + "?"
  }
  if starts_with(t, "[]") {
    return "Array[" + map_type(t[2:].to_owned()) + "]"
  }
  if starts_with(t, "map[") {
    let close = index_of(t, ']', 4)
    if close > 4 {
      let key = t[4:close].to_owned()
      let value = t[close + 1:].to_owned()
      return "Map[" + map_type(key) + ", " + map_type(value) + "]"
    }
  }
  match t {
    "string" => "String"
    "bool" => "Bool"
    "int" | "int8" | "int16" | "int32" | "rune" => "Int"
    "int64" => "Int64"
    "uint" | "uint8" | "uint16" | "uint32" => "UInt"
    "uint64" => "UInt64"
    "byte" => "Byte"
    "bytes" => "Bytes"
    "float32" => "Float"
    "float" | "float64" | "double" => "Double"
    _ => t
  }
}

///|
/// Whitespace-split a line into tokens, keeping a `"quoted string"` as one token
/// (with the quotes stripped).
fn tokens(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && is_ws(s[i]) {
      i = i + 1
    }
    if i >= n {
      break
    }
    if s[i] == '"' {
      let start = i + 1
      let mut j = start
      while j < n && s[j] != '"' {
        j = j + 1
      }
      out.push(s[start:j].to_owned())
      i = j + 1
    } else {
      let start = i
      while i < n && is_ws(s[i]) == false {
        i = i + 1
      }
      out.push(s[start:i].to_owned())
    }
  }
  out
}

///|
/// A spec the parser could not read: `Syntax` is the 1-based `line` and what went
/// wrong there, `Missing` an `import` whose `path` was not among the files handed to
/// `parse_all`.
pub suberror SpecError {
  Syntax(line~ : Int, msg~ : String)
  Missing(file~ : String, path~ : String)
}

///|
impl Show for SpecError with fn output(self, logger) {
  match self {
    Syntax(line~, msg~) =>
      logger.write_string("line " + line.to_string() + ": " + msg)
    Missing(file~, path~) =>
      logger.write_string(file + ": cannot read import \"" + path + "\"")
  }
}

///|
/// The `@server( … )` annotations governing a block of routes (← goctl's route
/// group): the `name` under which its routes are grouped, the path `prefix`
/// already folded into their paths, the `jwt` claim type, the `middleware` chain,
/// the `max_bytes` request cap (`0` when unset), the request `timeout`, and
/// whether the group's requests are signed. `extra` keeps every other annotation
/// the block carried, in order — goctl lets a spec invent its own, and dropping
/// them would lose what the author wrote.
pub(all) struct Group {
  name : String
  prefix : String
  jwt : String
  middleware : Array[String]
  max_bytes : Int64
  timeout : String
  signature : Bool
  extra : Array[(String, String)]
}

///|
/// One route in a service spec: HTTP verb (lower-cased), path pattern (with its
/// group's prefix applied), handler name, an optional summary, and the `@server`
/// group it was declared under. A modern goctl route (`verb /path (Req) returns
/// (Resp)`) also carries its request/response type names (its `@doc` fills
/// `summary`); both are empty for the legacy inline form (`verb /path handler
/// "summary"`).
pub(all) struct Route {
  verb : String
  path : String
  handler : String
  summary : String
  req : String
  resp : String
  group : Group?
}

///|
/// One field of a `type` block: its name, the (already MoonBit-mapped) type, and
/// the raw back-tick struct tag (`json:"…"`/`path`/`form`/`header`, empty when
/// absent) that carries the wire name and binding location.
pub(all) struct Field {
  name : String
  type_ : String
  tag : String
}

///|
/// A named message schema declared by a `type Name { field: Type … }` block,
/// generated into a MoonBit struct (goctl's request/response types). `embeds`
/// names the blocks it inlined — a bare `Base` line — whose fields belong to it as
/// if they had been written out; an anonymous nested block instead becomes a
/// `TypeDef` of its own, named after the two blocks, with a field pointing at it.
pub(all) struct TypeDef {
  name : String
  fields : Array[Field]
  embeds : Array[String]
}

///|
/// A parsed `.api` service specification. `groups` lists the `@server( … )` blocks
/// in the order they were declared; each route also points at the one it belongs
/// to. `imports` holds the `import` paths exactly as the file wrote them — relative
/// to the file itself, so resolving one needs the path it was read from; `deps` and
/// `parse_all` do that.
pub(all) struct Spec {
  service : String
  routes : Array[Route]
  types : Array[TypeDef]
  info : Array[(String, String)]
  groups : Array[Group]
  imports : Array[String]
}

///|
/// goctl only reads a line as a route when it opens with an HTTP verb; anything
/// else at that nesting level is an annotation or a brace.
fn is_http_verb(t : String) -> Bool {
  match t.to_lower() {
    "get"
    | "head"
    | "post"
    | "put"
    | "patch"
    | "delete"
    | "options"
    | "connect"
    | "trace" => true
    _ => false
  }
}

///|
/// What is left of `s` after its first `n` whitespace-separated tokens.
fn rest_after(s : String, n : Int) -> String {
  let len = s.length()
  let mut i = 0
  let mut seen = 0
  while seen < n && i < len {
    while i < len && is_ws(s[i]) {
      i = i + 1
    }
    while i < len && is_ws(s[i]) == false {
      i = i + 1
    }
    seen = seen + 1
  }
  trim(s[i:].to_owned())
}

///|
/// The text inside the first `( … )` pair of `s`, or "" when there is none.
fn paren_body(s : String) -> String {
  let lp = index_of(s, '(', 0)
  if lp < 0 {
    return ""
  }
  let rp = index_of(s, ')', lp + 1)
  if rp <= lp + 1 {
    return ""
  }
  trim(s[lp + 1:rp].to_owned())
}

///|
fn index_of_str(hay : String, needle : String) -> Int {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
/// Whether `s` spells a name: a letter or `_` first, then letters, digits, `_` and
/// the `.` a qualified type carries. What tells goctl's inline `Base` member from a
/// line that is simply missing its type.
fn is_name(s : String) -> Bool {
  let n = s.length()
  if n == 0 {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    let c = s[i]
    let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
    let ok = alpha || (i > 0 && ((c >= '0' && c <= '9') || c == '.'))
    if ok == false {
      return false
    }
  }
  true
}

///|
/// What a line inside a `type` block turned out to declare.
priv enum Member {
  /// An ordinary `name: type` / `Name Type` field.
  Plain(Field)
  /// goctl's inline member — a bare type name, whose own fields belong to the
  /// block that embedded it.
  Inline(String)
  /// `Name {`, an anonymous nested struct, with the tag the line carried.
  Nest(String, String)
}

///|
/// Read one `type`-block line. Accepts goctl's Go-struct field `Name Type` and
/// moonctl's colon form `name: type` (each with an optional back-tick tag), a bare
/// type name as an inline embed, and `Name {` as an anonymous nested struct.
/// Returns `None` for a line that is none of those, which the caller reports.
fn read_member(line : String) -> Member? {
  let mut decl = line
  let mut tag = ""
  let bt = index_of(line, '`', 0)
  if bt >= 0 {
    let close = index_of(line, '`', bt + 1)
    if close > bt {
      tag = line[bt + 1:close].to_owned()
      decl = trim(line[0:bt].to_owned() + " " + line[close + 1:].to_owned())
    }
  }
  if decl.length() > 0 && decl[decl.length() - 1] == '{' {
    let head = trim(decl[0:decl.length() - 1].to_owned())
    return if is_name(head) { Some(Nest(head, tag)) } else { None }
  }
  let colon = index_of(decl, ':', 0)
  if colon > 0 {
    let name = trim(decl[0:colon].to_owned())
    let type_ = map_type(decl[colon + 1:].to_owned())
    if type_ == "" {
      return None
    }
    return Some(Plain({ name, type_, tag, }))
  }
  let toks = tokens(decl)
  if toks.length() >= 2 {
    return Some(Plain({ name: toks[0], type_: map_type(toks[1]), tag, }))
  }
  if toks.length() == 1 && is_name(toks[0]) {
    return Some(Inline(toks[0]))
  }
  None
}

///|
/// Split on the commas outside a `"…"`, so a quoted value keeps the commas it
/// contains while `group: user, prefix: /api/v1` still separates.
fn split_commas(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut start = 0
  let mut in_str = false
  for i = 0; i < n; i = i + 1 {
    if s[i] == '"' {
      in_str = in_str == false
    } else if s[i] == ',' && in_str == false {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  out.push(s[start:n].to_owned())
  out
}

///|
/// Read the body of an `@server( … )` block into a `Group`. Each body line arrives
/// with its own number, so a complaint names the entry that caused it rather than
/// the line the block opened on. Entries separate on commas as well as newlines, so
/// both goctl's one-per-line layout and the compact `@server(group: user, prefix:
/// /api/v1)` form parse. A comma-separated fragment carrying no `key:` continues the
/// previous entry — that is how `middleware: Log,Trace` reads on a single line.
fn read_group(
  body : Array[(Int, String)],
  issues : Array[(Int, String)],
) -> Group {
  let entries : Array[(Int, String, String)] = []
  for chunk in body {
    for piece in split_commas(chunk.1) {
      let frag = trim(piece)
      if frag == "" {
        continue
      }
      let colon = index_of(frag, ':', 0)
      if colon <= 0 {
        if entries.length() == 0 {
          issues.push(
            (chunk.0, "@server entry \"" + frag + "\" is not `key: value`"),
          )
        } else {
          let last = entries.length() - 1
          let e = entries[last]
          entries[last] = (e.0, e.1, e.2 + "," + frag)
        }
        continue
      }
      entries.push(
        (
          chunk.0,
          trim(frag[0:colon].to_owned()),
          unquote(trim(frag[colon + 1:].to_owned())),
        ),
      )
    }
  }
  let mut name = ""
  let mut prefix = ""
  let mut jwt = ""
  let middleware : Array[String] = []
  let mut max_bytes = 0L
  let mut timeout = ""
  let mut signature = false
  let extra : Array[(String, String)] = []
  for kv in entries {
    match kv.1 {
      "group" => name = kv.2
      "prefix" => prefix = kv.2
      "jwt" => jwt = kv.2
      "middleware" =>
        for m in split_char(kv.2, ',') {
          let one = trim(m)
          if one != "" {
            middleware.push(one)
          }
        }
      "maxBytes" =>
        match to_i64(kv.2) {
          Some(v) => max_bytes = v
          None =>
            issues.push(
              (kv.0, "maxBytes: expected a number, got \"" + kv.2 + "\""),
            )
        }
      "timeout" => timeout = kv.2
      "signature" =>
        match kv.2 {
          "true" => signature = true
          "false" => signature = false
          _ =>
            issues.push(
              (kv.0, "signature: expected true or false, got \"" + kv.2 + "\""),
            )
        }
      _ => extra.push((kv.1, kv.2))
    }
  }
  { name, prefix, jwt, middleware, max_bytes, timeout, signature, extra, }
}

///|
/// Close every `type` block still open, innermost first, complaining about each at
/// the line it opened on. The blocks are already in `Spec.types`, so what they did
/// declare survives a missing brace.
fn unwind(open : Array[(TypeDef, Int)], issues : Array[(Int, String)]) -> Unit {
  while open.length() > 0 {
    match open.pop() {
      Some(f) =>
        issues.push((f.1, "type " + f.0.name + " is missing its closing `}`"))
      None => ()
    }
  }
}

///|
/// Read the body of a `@doc( … )` block into the route summary. goctl documents
/// `summary`, and `description` stands in for it when a block carries only that;
/// any other key is a typo worth naming, since a silently dropped one would leave
/// the route undocumented.
fn read_doc(
  body : Array[(Int, String)],
  issues : Array[(Int, String)],
) -> String {
  let mut summary = ""
  let mut description = ""
  for chunk in body {
    let frag = trim(chunk.1)
    if frag == "" {
      continue
    }
    let colon = index_of(frag, ':', 0)
    if colon <= 0 {
      issues.push((chunk.0, "@doc entry \"" + frag + "\" is not `key: value`"))
      continue
    }
    let key = trim(frag[0:colon].to_owned())
    let value = unquote(trim(frag[colon + 1:].to_owned()))
    match key {
      "summary" => summary = value
      "description" => description = value
      _ =>
        issues.push(
          (chunk.0, "@doc entry \"" + key + "\" is not summary or description"),
        )
    }
  }
  if summary == "" {
    description
  } else {
    summary
  }
}

///|
/// A handler name for a route that named none: the verb and the path's own
/// segments. A spec that forgot several `@handler`s still describes several
/// distinct handlers, so `parse_lenient` generates functions that differ rather
/// than one name declared twice; `parse` reports the omission either way.
fn fallback_handler(verb : String, path : String) -> String {
  let mut out = verb
  for seg in path_segments(path) {
    let mut word = ""
    for i = 0; i < seg.length(); i = i + 1 {
      let c = seg[i]
      if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' {
        word = word + seg[i:i + 1].to_owned()
      }
    }
    if word != "" {
      out = out + "_" + word
    }
  }
  to_snake(out + "_handler")
}

///|
/// Whether `s` opens with the annotation `name` itself rather than merely starting
/// with its letters: `@docs` is an annotation of its own, not a misspelt `@doc`, and
/// reading it as one would attach its text to the next route.
fn is_annot(s : String, name : String) -> Bool {
  if starts_with(s, name) == false {
    return false
  }
  let n = name.length()
  s.length() == n || is_ws(s[n]) || s[n] == '(' || s[n] == '"'
}

///|
/// The `"…"`-quoted paths in `s`, in the order they appear.
fn quoted_paths(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut i = 0
  while i < n {
    if s[i] == '"' {
      let start = i + 1
      let mut j = start
      while j < n && s[j] != '"' {
        j = j + 1
      }
      out.push(s[start:j].to_owned())
      i = j + 1
    } else {
      i = i + 1
    }
  }
  out
}

///|
/// Scan a `.api` source into a `Spec` plus every line the parser could not read.
/// Scanning always runs to the end, so one typo does not hide the rest.
fn read(source : String) -> (Spec, Array[(Int, String)]) {
  let issues : Array[(Int, String)] = []
  let mut service = "app"
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let info : Array[(String, String)] = []
  let groups : Array[Group] = []
  let imports : Array[String] = []
  let mut in_import = false
  let mut import_line = 0
  // The `type` blocks still open, outermost first: a nested block pushes onto it, a
  // `}` pops one, and whatever is left at the end was never closed.
  let open : Array[(TypeDef, Int)] = []
  let mut in_info = false
  let mut info_line = 0
  let mut in_type_group = false
  let mut type_group_line = 0
  let mut in_server = false
  let mut server_line = 0
  let server_body : Array[(Int, String)] = []
  let mut in_service = false
  let mut service_line = 0
  let mut group : Group? = None
  let mut pending_handler = ""
  let mut pending_doc = ""
  let mut in_doc = false
  let mut doc_line = 0
  let doc_body : Array[(Int, String)] = []
  let src = lines(source)
  for i = 0; i < src.length(); i = i + 1 {
    let no = i + 1
    let s = trim(strip_comment(src[i]))
    if s == "" {
      continue
    }
    if in_server {
      let close = index_of(s, ')', 0)
      let part = if close >= 0 { s[0:close].to_owned() } else { s }
      server_body.push((no, part))
      if close >= 0 {
        in_server = false
        let g = read_group(server_body, issues)
        groups.push(g)
        group = Some(g)
      }
      continue
    }
    if in_doc {
      let close = index_of(s, ')', 0)
      let part = if close >= 0 { s[0:close].to_owned() } else { s }
      doc_body.push((no, part))
      if close >= 0 {
        in_doc = false
        pending_doc = read_doc(doc_body, issues)
      }
      continue
    }
    // A grouped `import ( "a.api" "b.api" )` block: every quoted path in it is one
    // import, and the `)` closes the block.
    if in_import {
      let close = index_of(s, ')', 0)
      let part = trim(if close >= 0 { s[0:close].to_owned() } else { s })
      let found = quoted_paths(part)
      for p in found {
        imports.push(p)
      }
      if part != "" && found.length() == 0 {
        issues.push(
          (
            no,
            "expected a quoted path in the import group, got \"" + part + "\"",
          ),
        )
      }
      if close >= 0 {
        in_import = false
      }
      continue
    }
    // An `info ( key: "value" … )` block (← goctl's `info(...)`): its members feed
    // the OpenAPI `info` object. `syntax = "v1"` is recorded and skipped so it is
    // not mistaken for a route.
    if in_info {
      if starts_with(s, ")") {
        in_info = false
      } else {
        let colon = index_of(s, ':', 0)
        if colon > 0 {
          info.push(
            (
              trim(s[0:colon].to_owned()),
              unquote(trim(s[colon + 1:].to_owned())),
            ),
          )
        } else {
          issues.push((no, "info entry \"" + s + "\" is not `key: value`"))
        }
      }
      continue
    }
    if starts_with(s, "syntax") {
      continue
    }
    if starts_with(s, "info") && index_of(s, '(', 0) >= 0 {
      in_info = true
      info_line = no
      continue
    }
    // `Name Type` is a field, so an unterminated block would otherwise swallow the
    // rest of the file. A line that opens a top-level statement cannot be a field:
    // take it as the closing brace that was left out, then read it as the statement
    // it is.
    let statement = s == "service" ||
      starts_with(s, "service ") ||
      starts_with(s, "type ") ||
      starts_with(s, "type(") ||
      starts_with(s, "import") ||
      starts_with(s, "@")
    if open.length() > 0 {
      let td = open[open.length() - 1].0
      if s == "}" {
        open.pop() |> ignore
        continue
      } else if statement {
        unwind(open, issues)
      } else {
        match read_member(s) {
          Some(Plain(f)) => td.fields.push(f)
          Some(Inline(name)) => td.embeds.push(name)
          Some(Nest(name, tag)) => {
            // MoonBit has no anonymous struct, so the nested block becomes a type of
            // its own named after the two, and the field points at it.
            let nested : TypeDef = {
              name: td.name + upper_first(name),
              fields: [],
              embeds: [],
            }
            types.push(nested)
            td.fields.push({ name, type_: nested.name, tag, })
            open.push((nested, no))
          }
          None =>
            issues.push(
              (no, "field \"" + s + "\" in type " + td.name + " has no type"),
            )
        }
        continue
      }
    }
    // A grouped `type ( … )` block declares each member as a bare `Name {` line;
    // the single `type Name {` form is handled below.
    if in_type_group {
      if starts_with(s, ")") {
        in_type_group = false
        continue
      } else if statement {
        in_type_group = false
        issues.push((type_group_line, "type group is missing its closing `)`"))
      } else if index_of(s, '{', 0) < 0 {
        issues.push(
          (no, "expected `Name {` in the type group, got \"" + s + "\""),
        )
        continue
      } else {
        let toks = tokens(s)
        if toks.length() >= 1 && toks[0] != "{" {
          let td : TypeDef = {
            name: drop_brace(toks[0]),
            fields: [],
            embeds: [],
          }
          types.push(td)
          open.push((td, no))
        }
        continue
      }
    }
    if starts_with(s, "service ") || s == "service" {
      let toks = tokens(s)
      let name = if toks.length() >= 2 { drop_brace(toks[1]) } else { "" }
      if name == "" {
        issues.push((no, "service needs a name"))
      } else {
        service = name
      }
      if index_of(s, '{', 0) < 0 {
        issues.push((no, "expected `{` after the service name"))
      } else {
        in_service = true
        service_line = no
      }
    } else if starts_with(s, "type ") || starts_with(s, "type(") {
      let toks = tokens(s)
      if starts_with(trim(s[4:].to_owned()), "(") {
        in_type_group = true
        type_group_line = no
      } else if toks.length() >= 2 && index_of(s, '{', 0) >= 0 {
        let td : TypeDef = {
          name: drop_brace(toks[1]),
          fields: [],
          embeds: [],
        }
        types.push(td)
        open.push((td, no))
      } else {
        issues.push(
          (no, "expected `type Name {` or `type (`, got \"" + s + "\""),
        )
      }
    } else if starts_with(s, "import") {
      // Both `import "a.api"` and the grouped `import ( … )`; a path is resolved
      // against the file that wrote it, which only `deps`/`parse_all` can do.
      let rest = trim(s[6:].to_owned())
      if starts_with(rest, "(") {
        let body = trim(rest[1:].to_owned())
        let close = index_of(body, ')', 0)
        for
          p in quoted_paths(
            if close >= 0 {
              body[0:close].to_owned()
            } else {
              body
            },
          ) {
          imports.push(p)
        }
        if close < 0 {
          in_import = true
          import_line = no
        }
      } else {
        let found = quoted_paths(rest)
        if found.length() == 0 {
          issues.push((no, "import needs a quoted path"))
        }
        for p in found {
          imports.push(p)
        }
      }
    } else if is_annot(s, "@doc") {
      // Three spellings: `@doc "text"`, `@doc("text")`, and goctl's block form
      // `@doc ( summary: "text" )`, which may run over several lines. The text is
      // whatever follows the name — `@doc("…")` carries no space to split on.
      let rest = trim(s[4:].to_owned())
      if starts_with(rest, "(") {
        let body = rest[1:].to_owned()
        let close = index_of(body, ')', 0)
        let inner = if close >= 0 { body[0:close].to_owned() } else { body }
        if starts_with(trim(inner), "\"") {
          pending_doc = unquote(trim(inner))
        } else if close >= 0 {
          pending_doc = read_doc([(no, inner)], issues)
        } else {
          in_doc = true
          doc_line = no
          doc_body.clear()
          doc_body.push((no, inner))
        }
      } else if starts_with(rest, "\"") {
        let close = index_of(rest, '"', 1)
        pending_doc = if close > 0 { rest[1:close].to_owned() } else { rest }
      } else {
        pending_doc = rest
      }
    } else if is_annot(s, "@handler") {
      let toks = tokens(s)
      if toks.length() >= 2 {
        pending_handler = toks[1]
      } else {
        issues.push((no, "@handler needs a name"))
      }
    } else if is_annot(s, "@server") {
      let lp = index_of(s, '(', 0)
      if lp < 0 {
        issues.push((no, "@server needs a `( … )` annotation list"))
      } else {
        let body = s[lp + 1:].to_owned()
        let close = index_of(body, ')', 0)
        if close >= 0 {
          let g = read_group([(no, body[0:close].to_owned())], issues)
          groups.push(g)
          group = Some(g)
        } else {
          in_server = true
          server_line = no
          server_body.clear()
          server_body.push((no, body))
        }
      }
    } else if starts_with(s, "@") {
      issues.push((no, "unknown annotation \"" + tokens(s)[0] + "\""))
    } else if s == "}" {
      if in_service {
        if pending_handler != "" {
          issues.push((no, "@handler " + pending_handler + " has no route"))
        }
        in_service = false
        group = None
        pending_handler = ""
        pending_doc = ""
      } else {
        issues.push((no, "unexpected `}`"))
      }
    } else {
      // A route is `verb /path`, optionally carrying `(Req)`, `returns (Resp)`, or
      // both; the legacy form instead names its handler inline and may add a quoted
      // summary.
      let toks = tokens(s)
      if toks.length() >= 2 && is_http_verb(toks[0]) {
        let rest = rest_after(s, 2)
        let mut req = ""
        let mut resp = ""
        let mut handler = pending_handler
        let mut summary = pending_doc
        if starts_with(rest, "(") {
          let rp = index_of(rest, ')', 1)
          if rp > 1 {
            req = trim(rest[1:rp].to_owned())
          }
          if rp >= 0 {
            let tail = trim(rest[rp + 1:].to_owned())
            if starts_with(tail, "returns") {
              resp = paren_body(tail)
            }
          }
        } else if starts_with(rest, "returns") {
          resp = paren_body(rest)
        } else if rest != "" {
          let lt = tokens(rest)
          if lt.length() >= 1 {
            handler = lt[0]
          }
          if lt.length() >= 2 {
            summary = lt[1]
          }
        }
        let verb = toks[0].to_lower()
        if handler == "" {
          issues.push(
            (
              no,
              "route " +
              verb +
              " " +
              toks[1] +
              " has no handler; name one with `@handler`",
            ),
          )
          handler = fallback_handler(verb, toks[1])
        }
        let prefix = match group {
          Some(g) => g.prefix
          None => ""
        }
        routes.push({
          verb,
          path: join_path(prefix, toks[1]),
          handler,
          summary,
          req,
          resp,
          group,
        })
        pending_handler = ""
        pending_doc = ""
      } else if is_http_verb(toks[0]) {
        issues.push((no, "route " + toks[0] + " needs a path"))
      } else if in_service || (toks.length() >= 2 && starts_with(toks[1], "/")) {
        issues.push((no, "unknown verb \"" + toks[0] + "\""))
      } else {
        issues.push((no, "unknown statement \"" + toks[0] + "\""))
      }
    }
  }
  unwind(open, issues)
  if in_doc {
    issues.push((doc_line, "@doc block is missing its closing `)`"))
  }
  if in_import {
    issues.push((import_line, "import block is missing its closing `)`"))
  }
  if in_info {
    issues.push((info_line, "info block is missing its closing `)`"))
  }
  if in_type_group {
    issues.push((type_group_line, "type group is missing its closing `)`"))
  }
  if in_server {
    issues.push((server_line, "@server block is missing its closing `)`"))
  }
  if in_service {
    issues.push(
      (service_line, "service " + service + " is missing its closing `}`"),
    )
  }
  ({ service, routes, types, info, groups, imports, }, issues)
}

///|
/// Read a goctl-style `.api` description into a `Spec`. Grammar (one statement per
/// line):
///
/// ```
/// syntax = "v1"
///
/// info (
///   title:   "greet"
///   version: "v2"
/// )
///
/// type LoginReq {
///   name: string
/// }
///
/// @server (
///   group:      user
///   prefix:     /api/v1
///   middleware: Log
/// )
/// service greet {
///   @doc "health check"
///   @handler ping
///   get /ping
///
///   @handler login
///   post /login (LoginReq) returns (LoginResp)
///
///   get /legacy legacy_handler "the inline form"
/// }
/// ```
///
/// A `type` block declares a message schema (its fields become a MoonBit struct);
/// field types use goctl's Go spellings (`string`, `int64`, `[]T`, `map[K]V`, …).
/// An `@server( … )` block annotates every route of the service block that follows
/// it: the routes carry its `prefix` in their paths and its `Group` on their
/// `group`. Verbs are lower-cased, blank lines and `//` comments are dropped.
///
/// Any other line raises a `SpecError` naming it — a misspelt verb or a missing
/// brace would otherwise generate a quietly truncated program. Use `parse_lenient`
/// for a best-effort read of a spec that is still being written.
pub fn parse(source : String) -> Spec raise SpecError {
  let (spec, issues) = read(source)
  if issues.length() > 0 {
    let mut first = issues[0]
    for it in issues {
      if it.0 < first.0 {
        first = it
      }
    }
    raise Syntax(line=first.0, msg=first.1)
  }
  spec
}

///|
/// `parse` without the diagnostics: a line the parser cannot read is skipped and
/// whatever the spec does describe is returned. For a caller that generates from a
/// half-written spec on every keystroke; anything that reports to a user should
/// call `parse`.
pub fn parse_lenient(source : String) -> Spec {
  read(source).0
}

///|
fn quote(s : String) -> String {
  "\"" + s + "\""
}

///|
/// A group's annotations spelled the way the spec wrote them, e.g. `group: user,
/// prefix: /api/v1, middleware: Log`. Empty for a group that carries nothing.
fn group_note(g : Group) -> String {
  let parts : Array[String] = []
  if g.name != "" {
    parts.push("group: " + g.name)
  }
  if g.prefix != "" {
    parts.push("prefix: " + g.prefix)
  }
  if g.jwt != "" {
    parts.push("jwt: " + g.jwt)
  }
  if g.middleware.length() > 0 {
    let mut ms = ""
    for m in g.middleware {
      ms = if ms == "" { m } else { ms + "," + m }
    }
    parts.push("middleware: " + ms)
  }
  if g.max_bytes > 0L {
    parts.push("maxBytes: " + g.max_bytes.to_string())
  }
  if g.timeout != "" {
    parts.push("timeout: " + g.timeout)
  }
  if g.signature {
    parts.push("signature: true")
  }
  for kv in g.extra {
    parts.push(kv.0 + ": " + kv.1)
  }
  let mut out = ""
  for p in parts {
    out = if out == "" { p } else { out + ", " + p }
  }
  out
}

///|
/// Generate compilable moonapi scaffolding from a spec: a MoonBit struct for
/// every `type` block, a `build_app` that wires every route to its handler, plus
/// a stub for each handler. The routing part depends only on `moonbitstack/moonapi`
/// and `moonbitstack/moonasgi`; the emitted schemas are dependency-free.
///
/// Pass `template` to render the spec through the runtime template engine (see
/// `generate_with`) instead of the built-in generator; omit it for the default
/// scaffold.
pub fn generate(spec : Spec, template? : String) -> String raise TemplateError {
  match template {
    Some(src) => generate_with(spec, src)
    None => generate_builtin(spec)
  }
}

///|
/// The `TypeDef` named `name`, or `None` when the spec declared no such block.
fn find_type(types : Array[TypeDef], name : String) -> TypeDef? {
  for t in types {
    if t.name == name {
      return Some(t)
    }
  }
  None
}

///|
/// Every field a `type` block carries with its inline embeds folded in first,
/// which is both the shape an embedded Go struct serialises to and the only one
/// MoonBit can spell — a MoonBit struct has no embedding. An embed naming a block
/// that is not in `types`, and one that leads back to a block already folded in,
/// contribute nothing.
fn flat_fields(t : TypeDef, types : Array[TypeDef]) -> Array[Field] {
  let out : Array[Field] = []
  let seen : Array[String] = [t.name]
  fn walk(td : TypeDef) -> Unit {
    for name in td.embeds {
      if seen.contains(name) {
        continue
      }
      seen.push(name)
      match find_type(types, name) {
        Some(base) => walk(base)
        None => ()
      }
    }
    for f in td.fields {
      out.push(f)
    }
  }

  walk(t)
  out
}

///|
/// A MoonBit struct for every `type` block, in the order the spec declared them,
/// each followed by whatever its tags asked to be checked (see `render_checks`).
fn render_structs(types : Array[TypeDef]) -> String {
  let mut out = ""
  for t in types {
    let fields = flat_fields(t, types)
    out = out +
      "///|\n/// `" +
      t.name +
      "` schema (generated from the `.api` `type` block).\npub(all) struct " +
      t.name +
      " {\n"
    for f in fields {
      out = out + "  " + f.mbt_name() + " : " + f.type_ + "\n"
    }
    out = out + "}\n\n" + render_checks(t.name, fields)
  }
  out
}

///|
fn generate_builtin(spec : Spec) -> String {
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n" +
    render_structs(spec.types)
  out = out +
    "///|\n/// Build the " +
    spec.service +
    " application with its routes wired to handlers.\n"
  out = out + "pub fn build_app() -> @moonapi.App {\n"
  out = out + "  let app = @moonapi.App::new()\n"
  // A group's jwt / middleware / limits have no moonapi call to emit them into, so
  // the block they govern is marked with the annotations the spec asked for.
  let mut note = ""
  for r in spec.routes {
    let mark = match r.group {
      Some(g) => group_note(g)
      None => ""
    }
    if mark != note {
      out = out +
        (if mark == "" {
          "  // (ungrouped)\n"
        } else {
          "  // @server " + mark + "\n"
        })
      note = mark
    }
    // moonapi's `ApiHandler` is a *raising* fn-type, and under moonc 0.10.5 a pure
    // named fn no longer coerces to one. Register each handler through an arrow
    // closure — a closure infers the raise effect, so a stub that never raises and a
    // filled-in handler that raises an `HttpException` are both accepted unchanged.
    let handler = "ctx => " + r.handler + "(ctx)"
    let head = "  app." + r.verb + "(" + quote(r.path) + ", " + handler
    out = out +
      (if r.summary != "" {
        head + ", summary=" + quote(r.summary) + ")\n"
      } else {
        head + ")\n"
      })
  }
  out = out + "  app\n}\n\n"
  for r in spec.routes {
    let where_ = match r.group {
      Some(g) if g.name != "" => " of group " + g.name
      _ => ""
    }
    out = out +
      "///|\n/// `" +
      r.verb +
      " " +
      r.path +
      "`" +
      where_ +
      ".\npub fn " +
      r.handler +
      "(_ctx : @moonapi.Context) -> @moonasgi.Response {\n  @moonapi.text(200, " +
      quote("TODO: " + r.handler) +
      ")\n}\n\n"
  }
  out
}
