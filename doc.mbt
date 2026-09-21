///|
/// Target OpenAPI / Swagger document version. mctl emits every mainstream version
/// from one `.api` spec — the same shape moonapi's runtime emitter takes, so a
/// generated service and a hand-built moonapi app document the same way.
pub(all) enum DocVersion {
  Swagger20
  OpenApi30
  OpenApi31
} derive(Eq)

///|
pub extend DocVersion with Eq::{equal, not_equal}

///|
/// (root document key, version string) for a doc version.
fn doc_version_field(v : DocVersion) -> (String, String) {
  match v {
    Swagger20 => ("swagger", "2.0")
    OpenApi30 => ("openapi", "3.0.3")
    OpenApi31 => ("openapi", "3.1.0")
  }
}

///|
/// Split a URL path on `/`, dropping empty segments (so `/users/:id` → `["users",
/// ":id"]`).
fn path_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let n = path.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || path[i] == '/' {
      if i > start {
        out.push(path[start:i].to_owned())
      }
      start = i + 1
    }
  }
  out
}

///|
/// Rewrite an `.api` route path into OpenAPI form: a `:name` segment becomes
/// `{name}`, the notation both Swagger 2.0 and OpenAPI 3.x expect.
fn openapi_path(path : String) -> String {
  let mut out = "/"
  let segs = path_segments(path)
  for i = 0; i < segs.length(); i = i + 1 {
    if i > 0 {
      out = out + "/"
    }
    let seg = segs[i]
    if seg.length() > 0 && seg[0] == ':' {
      out = out + "{" + seg[1:].to_owned() + "}"
    } else {
      out = out + seg
    }
  }
  out
}

///|
/// The top-level `", "` in a `Map[K, V]` type spelling, tracking `[` `]` depth so a
/// nested `Map[Int, Array[String]]` splits on its own comma, not an inner one.
/// Returns the index of the comma, or `-1` if there is none at depth 0.
fn top_comma(s : String) -> Int {
  let n = s.length()
  let mut depth = 0
  for i = 0; i < n; i = i + 1 {
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
/// The `$ref` prefix for a component schema: `#/definitions/` in Swagger 2.0,
/// `#/components/schemas/` in OpenAPI 3.x.
fn ref_prefix(v : DocVersion) -> String {
  match v {
    Swagger20 => "#/definitions/"
    _ => "#/components/schemas/"
  }
}

///|
/// The JSON Schema for a MoonBit-spelled field type. Scalars carry an OpenAPI
/// `format` where one applies (`int64`, `double`, …); `Array[T]` becomes an array
/// with typed `items`; `Map[K, V]` an object with typed `additionalProperties`; an
/// unrecognised name is treated as another `type` block and emitted as a `$ref`.
fn type_schema(type_ : String, v : DocVersion) -> Json {
  let t = trim(type_)
  if starts_with(t, "Array[") && t[t.length() - 1] == ']' {
    let inner = t[6:t.length() - 1].to_owned()
    let schema : Map[String, Json] = Map([
      ("type", "array".to_json()),
      ("items", type_schema(inner, v)),
    ])
    return schema.to_json()
  }
  if starts_with(t, "Map[") && t[t.length() - 1] == ']' {
    let body = t[4:t.length() - 1].to_owned()
    let comma = top_comma(body)
    let value = if comma >= 0 {
      trim(body[comma + 1:].to_owned())
    } else {
      "String"
    }
    let schema : Map[String, Json] = Map([
      ("type", "object".to_json()),
      ("additionalProperties", type_schema(value, v)),
    ])
    return schema.to_json()
  }
  match t {
    "String" =>
      (Map([("type", "string".to_json())]) : Map[String, Json]).to_json()
    "Bool" =>
      (Map([("type", "boolean".to_json())]) : Map[String, Json]).to_json()
    "Int" | "UInt" =>
      (
        Map([("type", "integer".to_json()), ("format", "int32".to_json())]) :
        Map[String, Json]).to_json()
    "Int64" | "UInt64" =>
      (
        Map([("type", "integer".to_json()), ("format", "int64".to_json())]) :
        Map[String, Json]).to_json()
    "Double" =>
      (
        Map([("type", "number".to_json()), ("format", "double".to_json())]) :
        Map[String, Json]).to_json()
    "Float" =>
      (
        Map([("type", "number".to_json()), ("format", "float".to_json())]) :
        Map[String, Json]).to_json()
    "Byte" | "Bytes" =>
      (Map([("type", "string".to_json())]) : Map[String, Json]).to_json()
    _ =>
      (Map([("$ref", (ref_prefix(v) + t).to_json())]) : Map[String, Json]).to_json()
  }
}

///|
/// An OpenAPI parameter object. Swagger 2.0 puts the type inline; OpenAPI 3.x nests
/// it under `schema` — the one structural difference between the two.
fn param_object(
  name : String,
  in_ : String,
  required : Bool,
  schema : Json,
  v : DocVersion,
) -> Json {
  let param : Map[String, Json] = Map([
    ("name", name.to_json()),
    ("in", in_.to_json()),
    ("required", required.to_json()),
  ])
  match v {
    Swagger20 =>
      match schema {
        Object(m) =>
          for kv in m {
            param[kv.0] = kv.1
          }
        _ => param["type"] = "string".to_json()
      }
    _ => param["schema"] = schema
  }
  param.to_json()
}

///|
/// A `:name` path parameter as an OpenAPI parameter object.
fn path_param(name : String, v : DocVersion) -> Json {
  param_object(
    name,
    "path",
    true,
    (Map([("type", "string".to_json())]) : Map[String, Json]).to_json(),
    v,
  )
}

///|
/// Where a non-body field appears in an OpenAPI operation.
fn bind_in(b : Bind) -> String {
  match b {
    Query => "query"
    Path => "path"
    Header => "header"
    Body => "body"
  }
}

///|
/// The parameters a request type declares through its tags: a `form:` field is a
/// query parameter, a `path:` field a path parameter under the name its tag gives,
/// a `header:` field a header. A path parameter is always required; the others
/// follow the field's `optional`.
fn type_params(
  t : TypeDef,
  types : Array[TypeDef],
  v : DocVersion,
) -> Array[Json] {
  let out : Array[Json] = []
  for f in flat_fields(t, types) {
    let b = f.bind()
    if b == Body {
      continue
    }
    out.push(
      param_object(
        f.json_name(),
        bind_in(b),
        b == Path || f.optional() == false,
        field_schema(f, v),
        v,
      ),
    )
  }
  out
}

///|
/// The parameters of a route: the ones its request type's tags declare, then a path
/// parameter for every `:name` segment the type did not already name.
fn route_params(
  r : Route,
  types : Array[TypeDef],
  v : DocVersion,
) -> Array[Json] {
  let out : Array[Json] = []
  let named : Array[String] = []
  match find_type(types, r.req) {
    Some(t) => {
      for f in flat_fields(t, types) {
        if f.bind() != Body {
          named.push(f.json_name())
        }
      }
      for p in type_params(t, types, v) {
        out.push(p)
      }
    }
    None => ()
  }
  for seg in path_segments(r.path) {
    if seg.length() > 0 && seg[0] == ':' {
      let name = seg[1:].to_owned()
      if named.contains(name) == false {
        out.push(path_param(name, v))
      }
    }
  }
  out
}

///|
/// The JSON literal of a `default=` / `options=` value, typed by the field it
/// constrains: a number for a numeric field, a boolean for a `Bool`, a string
/// otherwise.
fn literal_json(type_ : String, raw : String) -> Json {
  match type_ {
    "Bool" => if raw == "true" { true.to_json() } else { false.to_json() }
    "Int" | "Int64" | "UInt" | "UInt64" | "Double" | "Float" => number_json(raw)
    _ => raw.to_json()
  }
}

///|
/// The schema of one field: its type, plus whatever its tag constrained — the
/// `default=`, the `options=` as an `enum`, and the `range=` as bounds. 3.1 spells
/// an exclusive bound as the number itself, 2.0 and 3.0 as a flag beside an
/// inclusive one.
fn field_schema(f : Field, v : DocVersion) -> Json {
  let m = match type_schema(f.type_, v) {
    Object(m) => m
    other => return other
  }
  // A `$ref` may not be qualified by siblings, so a nested message carries nothing.
  if m.contains("$ref") {
    return m.to_json()
  }
  match f.default_() {
    Some(d) => m["default"] = literal_json(f.type_, d)
    None => ()
  }
  let allowed = f.options()
  if allowed.length() > 0 {
    let vals : Array[Json] = []
    for one in allowed {
      vals.push(literal_json(f.type_, one))
    }
    m["enum"] = vals.to_json()
  }
  match f.range() {
    Some(r) => {
      if r.lo != "" {
        let lo = literal_json(f.type_, r.lo)
        if r.lo_inc {
          m["minimum"] = lo
        } else {
          match v {
            OpenApi31 => m["exclusiveMinimum"] = lo
            _ => {
              m["minimum"] = lo
              m["exclusiveMinimum"] = true.to_json()
            }
          }
        }
      }
      if r.hi != "" {
        let hi = literal_json(f.type_, r.hi)
        if r.hi_inc {
          m["maximum"] = hi
        } else {
          match v {
            OpenApi31 => m["exclusiveMaximum"] = hi
            _ => {
              m["maximum"] = hi
              m["exclusiveMaximum"] = true.to_json()
            }
          }
        }
      }
    }
    None => ()
  }
  m.to_json()
}

///|
/// Whether a request type has anything left for the body once its `path:`, `form:`
/// and `header:` fields have gone to the parameters. A type the spec never declared
/// counts as a body, since nothing here can say otherwise.
fn has_body(t : TypeDef?, types : Array[TypeDef]) -> Bool {
  match t {
    None => true
    Some(td) => {
      for f in flat_fields(td, types) {
        if f.bind() == Body {
          return true
        }
      }
      false
    }
  }
}

///|
/// The component schema of a `type` block: an object of its body-bound properties,
/// keyed by wire name, listing the ones no tag marked `optional` as `required`. A
/// block that inlined others is their `allOf` — the shape an embedded Go struct
/// serialises to. `path:`, `form:` and `header:` fields are not in the body, so they
/// are documented as parameters instead of properties.
fn component_schema(t : TypeDef, v : DocVersion) -> Json {
  let props : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for f in t.fields {
    if f.bind() != Body {
      continue
    }
    props[f.json_name()] = field_schema(f, v)
    if f.optional() == false {
      required.push(f.json_name().to_json())
    }
  }
  let own : Map[String, Json] = Map([
    ("type", "object".to_json()),
    ("properties", props.to_json()),
  ])
  if required.length() > 0 {
    own["required"] = required.to_json()
  }
  if t.embeds.length() == 0 {
    return own.to_json()
  }
  let all : Array[Json] = []
  for name in t.embeds {
    all.push(
      (Map([("$ref", (ref_prefix(v) + name).to_json())]) : Map[String, Json]).to_json(),
    )
  }
  if props.length() > 0 {
    all.push(own.to_json())
  }
  (Map([("allOf", all.to_json())]) : Map[String, Json]).to_json()
}

///|
/// The value of an `info(...)` member (← goctl's `info` block), or `None` if the
/// spec declared no such key.
fn info_get(spec : Spec, key : String) -> String? {
  for kv in spec.info {
    if kv.0 == key {
      return Some(kv.1)
    }
  }
  None
}

///|
/// Build the OpenAPI / Swagger document for `spec` as a `Json` value. Routes fold
/// into `paths` → HTTP method → operation (with `operationId`, any `:name` path
/// parameters, and a 200 response); every `type` block becomes a component schema
/// (`definitions` in 2.0, `components/schemas` in 3.x). `version` selects the
/// document dialect; `title`/`api_version` fill the `info` block.
pub fn openapi_document(
  spec : Spec,
  version? : DocVersion = OpenApi31,
  title? : String = "",
  api_version? : String = "0.1.0",
) -> Json {
  let doc_title = if title != "" {
    title
  } else {
    match info_get(spec, "title") {
      Some(t) => t
      None => spec.service
    }
  }
  let paths : Map[String, Json] = Map([])
  for r in spec.routes {
    let op : Map[String, Json] = Map([("operationId", r.handler.to_json())])
    if r.summary != "" {
      op["summary"] = r.summary.to_json()
    }
    // A route's `@server` group is its OpenAPI tag — the same grouping goctl gives
    // handlers, and what a doc UI sections the operations by.
    match r.group {
      Some(g) => if g.name != "" { op["tags"] = [g.name.to_json()].to_json() }
      None => ()
    }
    let params = route_params(r, spec.types, version)
    // A modern route's `(Req)` becomes a typed request body (a 2.0 `in: body`
    // parameter / a 3.x `requestBody`); its `returns (Resp)` types the 200 response.
    // A request type whose fields all bind somewhere else — a query-only filter —
    // has no body to document.
    if r.req != "" && has_body(find_type(spec.types, r.req), spec.types) {
      let schema : Map[String, Json] = Map([
        ("$ref", (ref_prefix(version) + r.req).to_json()),
      ])
      match version {
        Swagger20 =>
          params.push(
            (
              Map([
                ("in", "body".to_json()),
                ("name", "body".to_json()),
                ("required", true.to_json()),
                ("schema", schema.to_json()),
              ]) : Map[String, Json]).to_json(),
          )
        _ => {
          let media : Map[String, Json] = Map([("schema", schema.to_json())])
          op["requestBody"] = (
            Map([
              ("required", true.to_json()),
              (
                "content",
                (
                  Map([("application/json", media.to_json())]) :
                  Map[String, Json]).to_json(),
              ),
            ]) : Map[String, Json]).to_json()
        }
      }
    }
    if params.length() > 0 {
      op["parameters"] = params.to_json()
    }
    let ok : Map[String, Json] = Map([("description", "OK".to_json())])
    if r.resp != "" {
      let schema : Map[String, Json] = Map([
        ("$ref", (ref_prefix(version) + r.resp).to_json()),
      ])
      match version {
        Swagger20 => ok["schema"] = schema.to_json()
        _ => {
          let media : Map[String, Json] = Map([("schema", schema.to_json())])
          ok["content"] = (
            Map([("application/json", media.to_json())]) : Map[String, Json]).to_json()
        }
      }
    }
    op["responses"] = (Map([("200", ok.to_json())]) : Map[String, Json]).to_json()
    let key = openapi_path(r.path)
    let item = match paths.get(key) {
      Some(Object(m)) => m
      _ => Map([])
    }
    item[r.verb.to_lower()] = op.to_json()
    paths[key] = item.to_json()
  }
  let defs : Map[String, Json] = Map([])
  for t in spec.types {
    defs[t.name] = component_schema(t, version)
  }
  let doc_version = match info_get(spec, "version") {
    Some(v) => v
    None => api_version
  }
  let info : Map[String, Json] = Map([
    ("title", doc_title.to_json()),
    ("version", doc_version.to_json()),
  ])
  match info_get(spec, "desc") {
    Some(d) => info["description"] = d.to_json()
    None =>
      match info_get(spec, "description") {
        Some(d) => info["description"] = d.to_json()
        None => ()
      }
  }
  let (root_key, version_str) = doc_version_field(version)
  let doc : Map[String, Json] = Map([
    (root_key, version_str.to_json()),
    ("info", info.to_json()),
    ("paths", paths.to_json()),
  ])
  let tags : Array[Json] = []
  for g in spec.groups {
    if g.name != "" {
      tags.push(
        (Map([("name", g.name.to_json())]) : Map[String, Json]).to_json(),
      )
    }
  }
  if tags.length() > 0 {
    doc["tags"] = tags.to_json()
  }
  if not_empty(defs) {
    match version {
      Swagger20 => doc["definitions"] = defs.to_json()
      _ =>
        doc["components"] = (
          Map([("schemas", defs.to_json())]) : Map[String, Json]).to_json()
    }
  }
  doc.to_json()
}

///|
/// Whether a `Map` has any entries. (`Map::is_empty` needs `Eq` on the value; a
/// direct length check does not.)
fn not_empty(m : Map[String, Json]) -> Bool {
  m.length() > 0
}

///|
/// Generate an OpenAPI / Swagger document from `spec`, stringified with two-space
/// indentation. `version` picks the dialect (Swagger 2.0 / OpenAPI 3.0 / 3.1).
pub fn generate_doc(
  spec : Spec,
  version? : DocVersion = OpenApi31,
  title? : String = "",
  api_version? : String = "0.1.0",
) -> String {
  @json.dumps(openapi_document(spec, version~, title~, api_version~), indent=2)
}

///|
/// A self-contained Swagger UI page for the document served at `spec_url`. The
/// same stub moonapi ships, so a generated service and a live app render alike.
pub fn swagger_ui_stub(
  spec_url? : String = "/openapi.json",
  title? : String = "API Docs",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>" +
  title +
  "</title>\n<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist/swagger-ui.css\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n<script src=\"https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js\"></script>\n<script>\nwindow.onload = () => { window.ui = SwaggerUIBundle({ url: \"" +
  spec_url +
  "\", dom_id: \"#swagger-ui\" }); };\n</script>\n</body>\n</html>\n"
}
