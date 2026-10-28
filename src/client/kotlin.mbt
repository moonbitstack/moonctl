// The Kotlin emitter. One `data class` per `type` block with `fromWire`, one
// method per route, and two ports the caller fills in: `Transport` for HTTP and
// `Codec` for JSON. JSON is left to the caller on purpose — a Kotlin project
// already has kotlinx.serialization, Gson or Jackson, and a generated client
// should not force a fourth one into the build.

///|
/// The Kotlin type a MoonBit one maps to.
fn kt_ty(ty : Ty) -> String {
  match ty {
    Opt(t) => kt_ty(t) + "?"
    List(t) => "List<" + kt_ty(t) + ">"
    Dict(k, v) =>
      match k {
        Named(n) =>
          "Map<" +
          (if n == "String" { "String" } else { "Long" }) +
          ", " +
          kt_ty(v) +
          ">"
        _ => "Map<String, " + kt_ty(v) + ">"
      }
    Named(n) =>
      match n {
        "String" | "Bytes" => "String"
        "Bool" => "Boolean"
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" => "Int"
        "Int64" | "UInt64" => "Long"
        "Float" => "Float"
        "Double" => "Double"
        "Json" | "Unit" => "Any?"
        _ => pascal(n)
      }
  }
}

///|
/// The `toInt` / `toLong` / `toDouble` a numeric leaf is read through, or `None`
/// for a leaf that is not a number.
fn kt_num(name : String) -> String? {
  match name {
    "Int" | "Int32" | "UInt" | "UInt32" | "Byte" => Some("Int")
    "Int64" | "UInt64" => Some("Long")
    "Float" => Some("Float")
    "Double" => Some("Double")
    _ => None
  }
}

///|
/// The expression that reads `expr` — an `Any?` out of the codec — as the value of
/// `ty`.
fn kt_decode(ty : Ty, expr : String) -> String {
  match ty {
    Opt(t) =>
      match t {
        List(e) =>
          "(" + expr + " as List<Any?>?)?.map { " + kt_decode(e, "it") + " }"
        Dict(_, v) =>
          "(" +
          expr +
          " as Map<String, Any?>?)?.mapValues { (_, e) -> " +
          kt_decode(v, "e") +
          " }"
        Named(n) =>
          match kt_num(n) {
            Some(c) => "(" + expr + " as Number?)?.to" + c + "()"
            None =>
              if is_scalar(n) {
                "(" + expr + " as " + kt_ty(Named(n)) + "?)"
              } else {
                expr +
                "?.let { " +
                pascal(n) +
                ".fromWire(it as Map<String, Any?>) }"
              }
          }
        Opt(_) => kt_decode(t, expr)
      }
    List(t) => "(" + expr + " as List<Any?>).map { " + kt_decode(t, "it") + " }"
    Dict(_, v) =>
      "(" +
      expr +
      " as Map<String, Any?>).mapValues { (_, e) -> " +
      kt_decode(v, "e") +
      " }"
    Named(n) =>
      match kt_num(n) {
        Some(c) => "(" + expr + " as Number).to" + c + "()"
        None =>
          if is_scalar(n) {
            "(" + expr + " as " + kt_ty(Named(n)) + ")"
          } else {
            pascal(n) + ".fromWire(" + expr + " as Map<String, Any?>)"
          }
      }
  }
}

///|
/// One model: the properties, the primary constructor, and the `fromWire` a codec's
/// `Map` is read through. `fromWire` lives on the companion so a route can call it
/// without an instance.
fn kt_type(t : @api.TypeDef, types : Array[@api.TypeDef]) -> Array[String] {
  let out : Array[String] = []
  let name = pascal(t.name)
  let fields = @api.flat_fields(t, types)
  out.push("/** One `" + t.name + "` of the spec. */")
  if fields.length() == 0 {
    out.push("class " + name + " {")
    out.push("    companion object {")
    out.push(
      "        fun fromWire(m: Map<String, Any?>): " +
      name +
      " = " +
      name +
      "()",
    )
    out.push("    }")
    out.push("}")
    out.push("")
    return out
  }
  out.push("data class " + name + "(")
  for f in fields {
    let decl = field_ty(f)
    out.push(
      "    val " +
      camel(f.json_name()) +
      ": " +
      kt_ty(decl) +
      (if is_nullable(decl) { " = null" } else { "" }) +
      ",",
    )
  }
  out.push(") {")
  out.push("    companion object {")
  out.push(
    "        fun fromWire(m: Map<String, Any?>): " + name + " = " + name + "(",
  )
  for f in fields {
    out.push(
      "            " +
      camel(f.json_name()) +
      " = " +
      kt_decode(field_ty(f), "m[\"" + f.json_name() + "\"]") +
      ",",
    )
  }
  out.push("        )")
  out.push("    }")
  out.push("}")
  out.push("")
  out
}

///|
/// The path a method requests, as one Kotlin string concatenation of the literal
/// segments and the escaped parameters between them.
fn kt_path(op : Op) -> String {
  let parts : Array[String] = []
  let mut lit = ""
  for seg in @text.path_segments(op.path) {
    if seg.length() > 0 && seg[0] == ':' {
      if lit != "" {
        parts.push("\"" + lit + "/\"")
        lit = ""
      }
      parts.push("enc(" + camel(seg[1:].to_owned()) + ")")
    } else {
      lit = lit + "/" + seg
    }
  }
  if lit != "" {
    parts.push("\"" + lit + "\"")
  }
  if parts.length() == 0 {
    return "\"/\""
  }
  parts.join(" + ")
}

///|
/// One route as one method. Optional parameters carry `= null`, so a caller writes
/// only the arguments a route needs.
fn kt_method(op : Op) -> Array[String] {
  let out : Array[String] = []
  let params : Array[String] = []
  for (name, ty, required) in ordered_params(op) {
    if name == "body" {
      params.push("body: " + ty)
    } else {
      params.push(
        name +
        ": " +
        kt_ty(if required { parse_ty(ty) } else { opt_of(parse_ty(ty)) }) +
        (if required { "" } else { " = null" }),
      )
    }
  }
  if op.summary != "" {
    out.push("    /** " + op.summary + " */")
  }
  out.push(
    "    fun " +
    op.handler +
    "(" +
    params.join(", ") +
    ")" +
    (if op.resp == "" { "" } else { ": " + op.resp }) +
    " {",
  )
  out.push("        val path = " + kt_path(op))
  if op.query_params.length() > 0 {
    out.push("        val query = mutableListOf<String>()")
    for p in op.query_params {
      if p.optional {
        out.push("        if (" + p.field + " != null) {")
        out.push(
          "            query.add(\"" + p.wire + "=\" + enc(" + p.field + "))",
        )
        out.push("        }")
      } else {
        out.push(
          "        query.add(\"" + p.wire + "=\" + enc(" + p.field + "))",
        )
      }
    }
    out.push(
      "        val url = baseUrl + path + (if (query.isEmpty()) \"\" else \"?\" + query.joinToString(\"&\"))",
    )
  } else {
    out.push("        val url = baseUrl + path")
  }
  out.push(
    "        val headers = linkedMapOf(\"accept\" to \"application/json\")",
  )
  out.push(
    "        token?.let { headers[\"authorization\"] = \"Bearer \" + it }",
  )
  for p in op.header_params {
    if p.optional {
      out.push(
        "        " +
        p.field +
        "?.let { headers[\"" +
        p.wire +
        "\"] = it.toString() }",
      )
    } else {
      out.push(
        "        headers[\"" + p.wire + "\"] = " + p.field + ".toString()",
      )
    }
  }
  let body = if op.has_body {
    out.push("        headers[\"content-type\"] = \"application/json\"")
    "codec.encode(body)"
  } else {
    "null"
  }
  out.push(
    "        val res = transport.send(\"" +
    op.verb +
    "\", url, headers, " +
    body +
    ")",
  )
  out.push("        if (!res.ok) {")
  out.push("            throw ApiException(res.status, res.body)")
  out.push("        }")
  if op.resp != "" {
    out.push("        return " + op.resp + ".fromWire(codec.decode(res.body))")
  }
  out.push("    }")
  out.push("")
  out
}

///|
/// The whole file: the exception, the two ports, the models, then the client.
fn emit_kt(m : Model) -> String {
  let out : Array[String] = []
  out.push(
    "// Code generated by `mctl api kt` from a `.api` spec. DO NOT EDIT.",
  )
  out.push("//")
  out.push(
    "// " +
    m.service +
    " — a typed client for the MoonAPI routes of the spec.",
  )
  out.push("//")
  out.push(
    "// One route is one method: `path:` fields become parameters, `form:` fields",
  )
  out.push(
    "// become query parameters, `header:` fields become headers, and the `json:`",
  )
  out.push("// fields of the request type become the body.")
  out.push("//")
  out.push(
    "// Two ports, both the caller's: `Transport` sends a request, `Codec` turns a",
  )
  out.push(
    "// value into JSON and back. Back the codec with kotlinx.serialization, Gson or",
  )
  out.push(
    "// Jackson — a generated client forces no JSON library into your build.",
  )
  out.push("")
  out.push("import java.net.URLEncoder")
  out.push("")
  out.push("/** An answer the service did not send with a 2xx status. */")
  out.push(
    "class ApiException(val status: Int, val body: String) : RuntimeException(\"HTTP $status\")",
  )
  out.push("")
  out.push("/** One raw answer: the status and the text of the body. */")
  out.push("data class RawResponse(val status: Int, val body: String) {")
  out.push("    val ok: Boolean get() = status in 200..299")
  out.push("}")
  out.push("")
  out.push(
    "/** The transport port: send one request, get the raw answer back. */",
  )
  out.push("fun interface Transport {")
  out.push(
    "    fun send(method: String, url: String, headers: Map<String, String>, body: String?): RawResponse",
  )
  out.push("}")
  out.push("")
  out.push("/** The JSON port: encode a value, decode an object. */")
  out.push("interface Codec {")
  out.push("    fun encode(value: Any?): String")
  out.push("    fun decode(text: String): Map<String, Any?>")
  out.push("}")
  out.push("")
  out.push("/** One URL segment, escaped for a path or a query string. */")
  out.push("internal fun enc(value: Any?): String =")
  out.push(
    "    URLEncoder.encode(value.toString(), \"UTF-8\").replace(\"+\", \"%20\")",
  )
  out.push("")
  for t in m.types {
    for line in kt_type(t, m.types) {
      out.push(line)
    }
  }
  out.push("class " + m.class_name + "(")
  out.push("    baseUrl: String,")
  out.push("    private val transport: Transport,")
  out.push("    private val codec: Codec,")
  out.push("    var token: String? = null,")
  out.push(") {")
  out.push("    /** Base URL of the service; a trailing slash is dropped. */")
  out.push("    val baseUrl: String = baseUrl.trimEnd('/')")
  out.push("")
  for op in m.ops {
    for line in kt_method(op) {
      out.push(line)
    }
  }
  out.push("}")
  @text.join_lines(out)
}
