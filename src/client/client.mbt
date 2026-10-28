// `mctl api ts|dart|kt|java`: the typed clients goctl ships for TypeScript and
// leaves to plugins for everything else.
//
// One spec, one reading of it — `client_model` — and four emitters walking that
// model, so a route, a field or a type name is spelled the same way in every
// language. A client is typed end to end: the request type of a route becomes a
// model, the `path:` / `form:` / `header:` tags of its fields become method
// parameters, and its response type becomes the return type. Only the call itself
// is generated: transport is a port the caller fills in, so a generated client
// compiles with no third-party dependency and runs over fetch, dio, Ktor or
// anything else.

///|
/// The language a client is generated for: the four goctl generates or that the
/// community asks for.
pub(all) enum Lang {
  TypeScript
  Dart
  Kotlin
  Java
}

///|
/// The file extension a client of this language carries (`ts`, `dart`, `kt`,
/// `java`).
pub fn Lang::ext(self : Lang) -> String {
  match self {
    TypeScript => "ts"
    Dart => "dart"
    Kotlin => "kt"
    Java => "java"
  }
}

///|
/// How the language is spelled in a comment, e.g. `TypeScript`.
pub fn Lang::label(self : Lang) -> String {
  match self {
    TypeScript => "TypeScript"
    Dart => "Dart"
    Kotlin => "Kotlin"
    Java => "Java"
  }
}

///|
/// The file a client for `service` lands in: `greet_client.ts` and friends, named
/// after the service so two specs generated into one directory do not collide.
pub fn client_file_name(lang : Lang, service : String) -> String {
  let base = if service == "" { "api" } else { service }
  match lang {
    // `javac` insists a public class live in a file named after it, and the class is
    // named `GreetClient`, so the file is too
    Java => pascal(base) + "Client.java"
    _ => @text.to_snake(base) + "_client." + lang.ext()
  }
}

///|
/// A MoonBit type spelling read apart, so one shape drives four emitters:
/// `Array[Map[String, User]?]` becomes `List(Opt(Dict(Named("String"),
/// Named("User"))))` and each emitter renders that tree its own way.
priv enum Ty {
  Opt(Ty)
  List(Ty)
  Dict(Ty, Ty)
  Named(String)
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
/// Read a MoonBit type spelling apart. Anything this does not recognise stays a
/// `Named` leaf, which every emitter passes through as the name it was given — a
/// type moonctl has no mapping for is better carried across than guessed at.
fn parse_ty(raw : String) -> Ty {
  let s = @text.trim(raw)
  if s == "" {
    return Named("String")
  }
  if @text.starts_with(s, "Array[") && @text.ends_with(s, "]") {
    return List(parse_ty(s[6:s.length() - 1].to_owned()))
  }
  if @text.starts_with(s, "Map[") && @text.ends_with(s, "]") {
    let body = s[4:s.length() - 1].to_owned()
    let comma = top_comma(body)
    if comma >= 0 {
      return Dict(
        parse_ty(body[0:comma].to_owned()),
        parse_ty(body[comma + 1:].to_owned()),
      )
    }
    return Named(s)
  }
  if @text.ends_with(s, "?") && s.length() > 1 {
    return Opt(parse_ty(s[0:s.length() - 1].to_owned()))
  }
  Named(norm_name(s))
}

///|
/// A leaf spelled the way a `.api` file may spell it (`string`, `int64`,
/// `float64`), read as the MoonBit scalar it maps to. A spec's types are already
/// mapped by the parser, but the `?` a spec writes by hand — `string?` — skips that
/// pass, so the client normalizes every leaf it meets.
fn norm_name(n : String) -> String {
  match n {
    "string" => "String"
    "bool" => "Bool"
    "int" | "int8" | "int16" | "int32" | "rune" => "Int32"
    "int64" => "Int64"
    "uint" | "uint8" | "uint16" | "uint32" => "UInt32"
    "uint64" => "UInt64"
    "byte" => "Byte"
    "bytes" => "Bytes"
    "float32" => "Float"
    "float" | "float64" | "double" => "Double"
    _ => n
  }
}

///|
/// `t` marked optional, without stacking two `Opt`s: `int??` is not a type.
fn opt_of(t : Ty) -> Ty {
  match t {
    Opt(_) => t
    _ => Opt(t)
  }
}

///|
/// The type a field is carried as: its declared type, made nullable when its tag
/// says `optional` — a field that may be absent has to hold `null` in every
/// language a client is generated for.
fn field_ty(f : @api.Field) -> Ty {
  let ty = parse_ty(f.type_)
  if f.optional() {
    opt_of(ty)
  } else {
    ty
  }
}

///|
/// Whether a type may be absent: a nullable one, which a language spells `T?`,
/// `T | null` or a boxed `T`.
fn is_nullable(ty : Ty) -> Bool {
  match ty {
    Opt(_) => true
    _ => false
  }
}

///|
/// Whether a leaf names one of the scalars every language spells for itself, as
/// opposed to a `type` block of the spec.
fn is_scalar(name : String) -> Bool {
  match name {
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
/// One method parameter: the wire name the value is carried under, the property
/// name of the model field it came from, its MoonBit type, and whether the caller
/// may leave it out.
priv struct Param {
  wire : String
  field : String
  ty : String
  optional : Bool
}

///|
/// One route read as a client method.
priv struct Op {
  verb : String
  path : String
  handler : String
  summary : String
  req : String
  resp : String
  path_params : Array[Param]
  query_params : Array[Param]
  header_params : Array[Param]
  has_body : Bool
}

///|
/// A spec read as what the four emitters need: the client's name, the models it
/// carries and its methods in spec order.
priv struct Model {
  service : String
  class_name : String
  types : Array[@api.TypeDef]
  ops : Array[Op]
}

///|
/// One code point as a one-character string, with the case `f` asks for.
fn chr(c : UInt16) -> String {
  match c.to_char() {
    Some(ch) => ch.to_string()
    None => ""
  }
}

///|
/// `c` as a string, lower-cased when it is an ASCII capital.
fn chr_lower(c : UInt16) -> String {
  chr(if c >= 'A' && c <= 'Z' { c + 32 } else { c })
}

///|
/// `c` as a string, upper-cased when it is an ASCII lower-case letter.
fn chr_upper(c : UInt16) -> String {
  chr(if c >= 'a' && c <= 'z' { c - 32 } else { c })
}

///|
/// `user_name` / `UserName` / `X-Client-Id` → `userName`: the property name a model
/// field takes in every generated language. Any run of non-alphanumeric characters
/// is a word break, so a wire name a language cannot spell still lands on an
/// identifier that language accepts.
fn camel(name : String) -> String {
  let mut out = ""
  let mut up = false
  for i = 0; i < name.length(); i = i + 1 {
    let c = name[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9')
    if ok {
      if out.length() == 0 {
        out = out + chr_lower(c)
      } else if up {
        out = out + chr_upper(c)
      } else {
        out = out + chr(c)
      }
      up = false
    } else {
      up = out.length() > 0
    }
  }
  if out == "" {
    "field"
  } else {
    out
  }
}

///|
/// The type name of a `type` block or a route's payload: `user_name` → `UserName`,
/// `X-Client-Id` → `XClientId`.
fn pascal(name : String) -> String {
  @text.upper_first(camel(name))
}

///|
/// One field as a method parameter, taking the wire name from the field's binding
/// tag so `form:"page_size"` becomes `pageSize`.
fn param_of(f : @api.Field) -> Param {
  {
    wire: f.json_name(),
    field: camel(f.json_name()),
    ty: f.type_,
    optional: f.optional() || @text.ends_with(@text.trim(f.type_), "?"),
  }
}

///|
/// The fields of a route's request type that are bound from the body — what a
/// generated method sends as JSON, as opposed to what it puts in the URL.
fn body_fields(spec : @api.Spec, req : String) -> Array[@api.Field] {
  if req == "" {
    return []
  }
  let out : Array[@api.Field] = []
  match @api.find_type(spec.types, req) {
    None => ()
    Some(t) =>
      for f in @api.flat_fields(t, spec.types) {
        if f.bind() == @api.Body {
          out.push(f)
        }
      }
  }
  out
}

///|
/// The `:id` segments of a path, in the order they appear.
fn path_segments_raw(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in @text.path_segments(path) {
    if seg.length() > 1 && seg[0] == ':' {
      out.push(seg[1:].to_owned())
    }
  }
  out
}

///|
/// One route as a method. Path parameters take their type from the request type's
/// field of that name, and from `String` when the spec has none — a `:id` nothing
/// binds is a warning in `validate`, not a reason to refuse to generate.
fn op_of(spec : @api.Spec, r : @api.Route) -> Op {
  let fields = match @api.find_type(spec.types, r.req) {
    None => []
    Some(t) => @api.flat_fields(t, spec.types)
  }
  let path_params : Array[Param] = []
  for seg in path_segments_raw(r.path) {
    let mut found : Param? = None
    for f in fields {
      if f.json_name() == seg || f.mbt_name() == seg {
        found = Some(param_of(f))
      }
    }
    path_params.push(
      match found {
        Some(p) => { wire: seg, field: p.field, ty: p.ty, optional: false, }
        None => { wire: seg, field: camel(seg), ty: "String", optional: false, }
      },
    )
  }
  let query_params : Array[Param] = []
  let header_params : Array[Param] = []
  for f in fields {
    match f.bind() {
      @api.Query => query_params.push(param_of(f))
      @api.Header => header_params.push(param_of(f))
      _ => ()
    }
  }
  {
    verb: r.verb.to_upper(),
    path: r.path,
    handler: camel(r.handler),
    summary: r.summary,
    req: if r.req == "" {
      ""
    } else {
      pascal(r.req)
    },
    resp: if r.resp == "" {
      ""
    } else {
      pascal(r.resp)
    },
    path_params,
    query_params,
    header_params,
    has_body: body_fields(spec, r.req).length() > 0,
  }
}

///|
/// The spec read as a client: `greet` → `GreetClient`, every `type` block as a
/// model, every route as a method.
fn client_model(spec : @api.Spec) -> Model {
  let service = spec.service
  let base = if service == "" { "api" } else { service }
  let ops : Array[Op] = []
  for r in spec.routes {
    ops.push(op_of(spec, r))
  }
  {
    service: base,
    class_name: pascal(base) + "Client",
    types: spec.types,
    ops,
  }
}

///|
/// Generate the client of `lang` for `spec`. The result is one file: the models the
/// spec declares, then the client class, in that order, so a reader meets the data
/// before the calls that carry it.
pub fn generate_client(spec : @api.Spec, lang : Lang) -> String {
  let m = client_model(spec)
  match lang {
    TypeScript => emit_ts(m)
    Dart => emit_dart(m)
    Kotlin => emit_kt(m)
    Java => emit_java(m)
  }
}

///|
/// The file name and the source of the client `lang` for `spec`, which is what
/// `mctl api ts <file.api>` writes.
pub fn client_file(spec : @api.Spec, lang : Lang) -> (String, String) {
  (client_file_name(lang, spec.service), generate_client(spec, lang))
}

///|
/// A method's parameters in the order every emitter writes them: the body first
/// (a client call reads `create(req, id)`), then the path segments, then the
/// optional `query` and `header` ones — required before optional, because
/// TypeScript refuses a required parameter after an optional one.
fn ordered_params(op : Op) -> Array[(String, String, Bool)] {
  let out : Array[(String, String, Bool)] = []
  if op.has_body {
    out.push(("body", op.req, true))
  }
  for p in op.path_params {
    out.push((p.field, p.ty, true))
  }
  for p in op.query_params {
    out.push((p.field, p.ty, p.optional == false))
  }
  for p in op.header_params {
    out.push((p.field, p.ty, p.optional == false))
  }
  // a required parameter never follows an optional one
  let required : Array[(String, String, Bool)] = []
  let optional : Array[(String, String, Bool)] = []
  for p in out {
    if p.2 {
      required.push(p)
    } else {
      optional.push(p)
    }
  }
  required + optional
}

///|
/// The `:id` a path segment is filled from, as an expression for `lang`: the
/// segment's parameter value, escaped for a URL.
fn path_value(lang : Lang, name : String) -> String {
  match lang {
    TypeScript => "encodeURIComponent(String(" + name + "))"
    Dart => "Uri.encodeComponent(" + name + ".toString())"
    Kotlin => "enc(" + name + ")"
    Java => "enc(" + name + ")"
  }
}

///|
/// The two characters `${`, built at run time rather than written as one literal:
/// the JS backend emits a MoonBit string as a template literal, where that pair
/// would start an interpolation. Every generated `${` — a TypeScript template
/// literal, a Dart string — goes through this.
fn interp_open() -> String {
  "$" + chr(0x7B)
}

///|
/// Whether a type tree mentions a `type` block, in which case a value of it has to
/// be converted rather than passed on as it is.
fn mentions_named(ty : Ty) -> Bool {
  match ty {
    Opt(t) => mentions_named(t)
    List(t) => mentions_named(t)
    Dict(k, v) => mentions_named(k) || mentions_named(v)
    Named(n) => is_scalar(n) == false
  }
}
