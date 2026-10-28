// The TypeScript emitter (goctl's `api ts`). One interface per `type` block, one
// `fromJson`/`toJson` pair per interface, one async method per route. The transport
// is a `Fetch` port that defaults to the global `fetch`, so the file needs no
// `npm install` and type-checks with `tsc --strict`.

///|
/// The TypeScript type a MoonBit one maps to: numbers collapse to `number`, a
/// `Map` becomes a `Record`, and a `type` block keeps its name.
fn ts_ty(ty : Ty) -> String {
  match ty {
    Opt(t) => {
      let inner = ts_ty(t)
      let wrapped = if @text.index_of_str(inner, "|") >= 0 {
        "(" + inner + ")"
      } else {
        inner
      }
      wrapped + " | null"
    }
    List(t) => {
      let e = ts_ty(t)
      if @text.index_of_str(e, "|") >= 0 || @text.index_of_str(e, "&") >= 0 {
        "(" + e + ")[]"
      } else {
        e + "[]"
      }
    }
    Dict(k, v) =>
      match k {
        Named(n) =>
          "Record<" +
          (if n == "String" { "string" } else { "number" }) +
          ", " +
          ts_ty(v) +
          ">"
        _ => "Record<string, " + ts_ty(v) + ">"
      }
    Named(n) =>
      match n {
        "String" => "string"
        "Bool" => "boolean"
        "Int"
        | "Int32"
        | "UInt"
        | "UInt32"
        | "Byte"
        | "Int64"
        | "UInt64"
        | "Float"
        | "Double" => "number"
        "Bytes" => "string"
        "Json" => "unknown"
        "Unit" => "void"
        _ => pascal(n)
      }
  }
}

///|
/// Whether `s` can stand as a property name without quotes.
fn ts_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    let alpha = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      c == '$'
    let digit = c >= '0' && c <= '9'
    if alpha == false && (i == 0 || digit == false) {
      return false
    }
  }
  true
}

///|
/// A property name as written in an interface: bare when it is an identifier,
/// quoted otherwise, so `user-name` still lands on the right key.
fn ts_prop(s : String) -> String {
  if ts_ident(s) {
    s
  } else {
    "\"" + s + "\""
  }
}

///|
/// The value an emitted expression has to be converted through, or the expression
/// itself when the type is already JSON-shaped.
fn ts_encode(ty : Ty, expr : String) -> String {
  if mentions_named(ty) == false {
    return expr
  }
  match ty {
    Opt(t) => ts_encode(t, expr)
    List(t) => expr + ".map((e: any) => " + ts_encode(t, "e") + ")"
    Dict(_, v) =>
      "Object.fromEntries(Object.entries(" +
      expr +
      ").map(([k, e]) => [k, " +
      ts_encode(v, "e") +
      "]))"
    Named(n) => camel(n) + "ToJson(" + expr + ")"
  }
}

///|
/// One `interface` and the pair of functions that move it to and from JSON. The
/// decoder is a plain object literal — `JSON.parse` already gives the right
/// shapes — and the encoder drops the fields the caller left out, so an optional
/// field is absent rather than null.
fn ts_type(t : @api.TypeDef, types : Array[@api.TypeDef]) -> Array[String] {
  let out : Array[String] = []
  let name = pascal(t.name)
  let fields = @api.flat_fields(t, types)
  out.push("export interface " + name + " {")
  for f in fields {
    let decl = if f.optional() { "?" } else { "" }
    out.push(
      "  " +
      ts_prop(camel(f.json_name())) +
      decl +
      ": " +
      ts_ty(field_ty(f)) +
      ";",
    )
  }
  out.push("}")
  out.push("")
  out.push(
    "export function " + camel(t.name) + "FromJson(raw: any): " + name + " {",
  )
  out.push("  return {")
  for f in fields {
    let key = camel(f.json_name())
    let value = if f.optional() {
      "raw[\"" + f.json_name() + "\"] ?? undefined"
    } else {
      "raw[\"" + f.json_name() + "\"]"
    }
    out.push("    " + ts_prop(key) + ": " + value + ",")
  }
  out.push("  };")
  out.push("}")
  out.push("")
  out.push(
    "export function " + camel(t.name) + "ToJson(value: " + name + "): any {",
  )
  out.push("  const out: any = {};")
  for f in fields {
    let key = f.json_name()
    let value = ts_encode(field_ty(f), "value." + camel(key))
    if f.optional() {
      out.push(
        "  if (value." +
        camel(key) +
        " !== undefined && value." +
        camel(key) +
        " !== null) {",
      )
      out.push("    out[\"" + key + "\"] = " + value + ";")
      out.push("  }")
    } else {
      out.push("  out[\"" + key + "\"] = " + value + ";")
    }
  }
  out.push("  return out;")
  out.push("}")
  out.push("")
  out
}

///|
/// The path a method requests, as one template literal with `${…}` where a `:seg`
/// was.
fn ts_path(op : Op) -> String {
  let mut out = "`"
  for seg in @text.path_segments(op.path) {
    if seg.length() > 0 && seg[0] == ':' {
      out = out +
        "/" +
        interp_open() +
        path_value(TypeScript, camel(seg[1:].to_owned())) +
        "}"
    } else {
      out = out + "/" + seg
    }
  }
  if out == "`" {
    out = "`/`"
  }
  out + "`"
}

///|
/// One route as one `async` method: URL, query string, headers, body, and the
/// status check every method repeats.
fn ts_method(op : Op) -> Array[String] {
  let out : Array[String] = []
  let params : Array[String] = []
  for (name, ty, required) in ordered_params(op) {
    let t = if name == "body" { ty } else { ts_ty(parse_ty(ty)) }
    params.push(name + (if required { "" } else { "?" }) + ": " + t)
  }
  let ret = if op.resp == "" { "void" } else { op.resp }
  if op.summary != "" {
    out.push("  /** " + op.summary + " */")
  }
  out.push(
    "  async " +
    op.handler +
    "(" +
    params.join(", ") +
    "): Promise<" +
    ret +
    "> {",
  )
  out.push("    const path = " + ts_path(op) + ";")
  if op.query_params.length() > 0 {
    out.push("    const query: string[] = [];")
    for p in op.query_params {
      let opener = if p.optional {
        "if (" + p.field + " !== undefined && " + p.field + " !== null) {"
      } else {
        "{"
      }
      out.push("    " + opener)
      out.push(
        "      query.push(\"" +
        p.wire +
        "=\" + " +
        path_value(TypeScript, p.field) +
        ");",
      )
      out.push("    }")
    }
    out.push(
      "    const url = this.baseUrl + path + (query.length > 0 ? \"?\" + query.join(\"&\") : \"\");",
    )
  } else {
    out.push("    const url = this.baseUrl + path;")
  }
  out.push(
    "    const headers: Record<string, string> = { accept: \"application/json\" };",
  )
  out.push("    if (this.token !== undefined) {")
  out.push("      headers[\"authorization\"] = \"Bearer \" + this.token;")
  out.push("    }")
  for p in op.header_params {
    if p.optional {
      out.push("    if (" + p.field + " !== undefined) {")
      out.push("      headers[\"" + p.wire + "\"] = String(" + p.field + ");")
      out.push("    }")
    } else {
      out.push("    headers[\"" + p.wire + "\"] = String(" + p.field + ");")
    }
  }
  let init = if op.has_body {
    out.push("    headers[\"content-type\"] = \"application/json\";")
    "{ method: \"" +
    op.verb +
    "\", headers, body: JSON.stringify(" +
    camel(op.req) +
    "ToJson(body)) }"
  } else {
    "{ method: \"" + op.verb + "\", headers }"
  }
  out.push("    const res = await this.fetchImpl(url, " + init + ");")
  out.push("    const text = await res.text();")
  out.push("    if (!res.ok) {")
  out.push("      throw new ApiError(res.status, text);")
  out.push("    }")
  if op.resp != "" {
    out.push("    return " + camel(op.resp) + "FromJson(JSON.parse(text));")
  }
  out.push("  }")
  out.push("")
  out
}

///|
/// The whole file: the error, the transport port, the models, then the client.
fn emit_ts(m : Model) -> String {
  let out : Array[String] = []
  out.push(
    "// Code generated by `mctl api ts` from a `.api` spec. DO NOT EDIT.",
  )
  out.push("//")
  out.push(
    "// " +
    m.service +
    " — a typed client for the MoonAPI routes of the spec.",
  )
  out.push("//")
  out.push(
    "// One route is one method: `path:` fields become leading parameters, `form:`",
  )
  out.push(
    "// fields become query parameters, `header:` fields become headers, and the",
  )
  out.push("// `json:` fields of the request type become the body.")
  out.push("//")
  out.push(
    "// The transport is a port — `new " +
    m.class_name +
    "(baseUrl, fetchImpl)` — and",
  )
  out.push(
    "// defaults to the global `fetch`, so this file compiles with `tsc --strict` and",
  )
  out.push("// no dependencies.")
  out.push("")
  out.push("export interface HttpResponse {")
  out.push("  readonly ok: boolean;")
  out.push("  readonly status: number;")
  out.push("  text(): Promise<string>;")
  out.push("}")
  out.push("")
  out.push("export type Fetch = (")
  out.push("  url: string,")
  out.push(
    "  init: { method: string; headers: Record<string, string>; body?: string },",
  )
  out.push(") => Promise<HttpResponse>;")
  out.push("")
  out.push("/** A response the service did not answer with 2xx. */")
  out.push("export class ApiError extends Error {")
  out.push("  constructor(")
  out.push("    readonly status: number,")
  out.push("    readonly body: string,")
  out.push("  ) {")
  out.push("    super(\"HTTP \" + status);")
  out.push("    this.name = \"ApiError\";")
  out.push("  }")
  out.push("}")
  out.push("")
  for t in m.types {
    for line in ts_type(t, m.types) {
      out.push(line)
    }
  }
  out.push("export class " + m.class_name + " {")
  out.push("  /** Base URL of the service; a trailing slash is dropped. */")
  out.push("  readonly baseUrl: string;")
  out.push("  /** Bearer token sent with every request while set. */")
  out.push("  token?: string;")
  out.push("  private readonly fetchImpl: Fetch;")
  out.push("")
  out.push(
    "  constructor(baseUrl: string, fetchImpl?: Fetch, token?: string) {",
  )
  out.push("    this.baseUrl = baseUrl.replace(/\\/+$/, \"\");")
  out.push(
    "    this.fetchImpl = fetchImpl ?? ((url, init) => fetch(url, init));",
  )
  out.push("    this.token = token;")
  out.push("  }")
  out.push("")
  for op in m.ops {
    for line in ts_method(op) {
      out.push(line)
    }
  }
  out.push("}")
  @text.join_lines(out)
}
