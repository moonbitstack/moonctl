// The Java emitter. Java allows one public top-level type per file, so the whole
// client is one public class: the two ports, the exception, the models and the
// calls are nested inside it, and a caller names them `GreetClient.User`. That is
// the price of a single generated file that `javac` accepts as it stands; the
// alternative is one file per model, which buries the route table a reader came
// for.
//
// JSON is the caller's, as in Kotlin: a `Codec` port takes a value and returns
// text, so Jackson, Gson or a hand-rolled reader all fit and the generated client
// needs no dependency.

///|
/// The Java type a MoonBit one maps to. Every leaf is boxed: generics cannot hold a
/// primitive, and a boxed field is the one spelling that works in a field, in a
/// `List` and in a parameter alike.
fn java_ty(ty : Ty) -> String {
  match ty {
    Opt(t) => java_ty(t)
    List(t) => "List<" + java_ty(t) + ">"
    Dict(k, v) =>
      match k {
        Named(n) =>
          "Map<" +
          (if n == "String" { "String" } else { "Long" }) +
          ", " +
          java_ty(v) +
          ">"
        _ => "Map<String, " + java_ty(v) + ">"
      }
    Named(n) =>
      match n {
        "String" | "Bytes" => "String"
        "Bool" => "Boolean"
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" => "Integer"
        "Int64" | "UInt64" => "Long"
        "Float" => "Float"
        "Double" => "Double"
        "Json" | "Unit" => "Object"
        _ => pascal(n)
      }
  }
}

///|
/// The plain Java type of a parameter that cannot be left out: a `long` rather than
/// a `Long`, so a required argument is a required argument at the call site too.
fn java_param_ty(ty : Ty, required : Bool) -> String {
  if required == false {
    return java_ty(ty)
  }
  match ty {
    Named(n) =>
      match n {
        "Bool" => "boolean"
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" => "int"
        "Int64" | "UInt64" => "long"
        "Float" => "float"
        "Double" => "double"
        _ => java_ty(ty)
      }
    _ => java_ty(ty)
  }
}

///|
/// The expression that reads `expr` — an `Object` out of the codec — as one value of
/// `ty`. Containers are cast, not walked: their elements were already read by the
/// loop that called this.
fn java_atom(ty : Ty, expr : String) -> String {
  match ty {
    Opt(t) => java_atom(t, expr)
    List(_) | Dict(_, _) => "(" + java_ty(ty) + ") " + expr
    Named(n) =>
      match n {
        "String" | "Bytes" => "(String) " + expr
        "Bool" => "(Boolean) " + expr
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" =>
          "((Number) " + expr + ").intValue()"
        "Int64" | "UInt64" => "((Number) " + expr + ").longValue()"
        "Float" => "((Number) " + expr + ").floatValue()"
        "Double" => "((Number) " + expr + ").doubleValue()"
        "Json" | "Unit" => expr
        _ => pascal(n) + ".fromWire(asMap(" + expr + "))"
      }
  }
}

///|
/// The statements that fill one field of a model out of the wire map, walking a
/// list or a map element by element so the element type stays checked.
fn java_decode_field(f : @api.Field) -> Array[String] {
  let ty = field_ty(f)
  let key = "\"" + f.json_name() + "\""
  let field = camel(f.json_name())
  match ty {
    List(t) => {
      let out : Array[String] = []
      out.push("            if (m.get(" + key + ") != null) {")
      out.push("                for (Object e : asList(m.get(" + key + "))) {")
      out.push(
        "                    out." + field + ".add(" + java_atom(t, "e") + ");",
      )
      out.push("                }")
      out.push("            }")
      out
    }
    Dict(_, v) => {
      let out : Array[String] = []
      out.push("            if (m.get(" + key + ") != null) {")
      out.push(
        "                for (Map.Entry<String, Object> e : asMap(m.get(" +
        key +
        ")).entrySet()) {",
      )
      out.push(
        "                    out." +
        field +
        ".put(e.getKey(), " +
        java_atom(v, "e.getValue()") +
        ");",
      )
      out.push("                }")
      out.push("            }")
      out
    }
    _ => {
      let out : Array[String] = []
      out.push("            if (m.get(" + key + ") != null) {")
      out.push(
        "                out." +
        field +
        " = " +
        java_atom(ty, "m.get(" + key + ")") +
        ";",
      )
      out.push("            }")
      out
    }
  }
}

///|
/// One model: public fields, a `fromWire` that reads the codec's map, and the
/// imports a `List` or a `Map` field needs already initialised so a caller can add
/// to it without a null check.
fn java_type(t : @api.TypeDef, types : Array[@api.TypeDef]) -> Array[String] {
  let out : Array[String] = []
  let name = pascal(t.name)
  let fields = @api.flat_fields(t, types)
  out.push("    /** One `" + t.name + "` of the spec. */")
  out.push("    public static final class " + name + " {")
  for f in fields {
    let ty = field_ty(f)
    let init = match ty {
      List(_) => " = new ArrayList<>()"
      Dict(_, _) => " = new LinkedHashMap<>()"
      _ => ""
    }
    out.push(
      "        public " + java_ty(ty) + " " + camel(f.json_name()) + init + ";",
    )
  }
  out.push("")
  out.push(
    "        public static " + name + " fromWire(Map<String, Object> m) {",
  )
  if fields.length() == 0 {
    out.push("            return new " + name + "();")
  } else {
    out.push("            " + name + " out = new " + name + "();")
    for f in fields {
      for line in java_decode_field(f) {
        out.push(line)
      }
    }
    out.push("            return out;")
  }
  out.push("        }")
  out.push("    }")
  out.push("")
  out
}

///|
/// The path a method requests, as one Java string concatenation.
fn java_path(op : Op) -> String {
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
/// One route as one method, plus the shorter overload that fills the optional
/// parameters with `null` — Java has no default arguments, and a caller that has
/// nothing to say about `page` should not have to spell it out.
fn java_method(op : Op) -> Array[String] {
  let out : Array[String] = []
  let params : Array[String] = []
  let short_decls : Array[String] = []
  let short_names : Array[String] = []
  let optional_names : Array[String] = []
  for (name, ty, required) in ordered_params(op) {
    let decl = if name == "body" {
      ty + " body"
    } else {
      java_param_ty(parse_ty(ty), required) + " " + name
    }
    params.push(decl)
    if required {
      short_decls.push(decl)
      short_names.push(name)
    } else {
      optional_names.push(name)
    }
  }
  if op.summary != "" {
    out.push("    /** " + op.summary + " */")
  }
  out.push(
    "    public " +
    (if op.resp == "" { "void" } else { op.resp }) +
    " " +
    op.handler +
    "(" +
    params.join(", ") +
    ") {",
  )
  out.push("        String path = " + java_path(op) + ";")
  if op.query_params.length() > 0 {
    out.push("        List<String> query = new ArrayList<>();")
    for p in op.query_params {
      if p.optional {
        out.push("        if (" + p.field + " != null) {")
        out.push(
          "            query.add(\"" + p.wire + "=\" + enc(" + p.field + "));",
        )
        out.push("        }")
      } else {
        out.push(
          "        query.add(\"" + p.wire + "=\" + enc(" + p.field + "));",
        )
      }
    }
    out.push(
      "        String url = baseUrl + path + (query.isEmpty() ? \"\" : \"?\" + String.join(\"&\", query));",
    )
  } else {
    out.push("        String url = baseUrl + path;")
  }
  out.push("        Map<String, String> headers = new LinkedHashMap<>();")
  out.push("        headers.put(\"accept\", \"application/json\");")
  out.push("        if (token != null) {")
  out.push("            headers.put(\"authorization\", \"Bearer \" + token);")
  out.push("        }")
  for p in op.header_params {
    if p.optional {
      out.push("        if (" + p.field + " != null) {")
      out.push(
        "            headers.put(\"" +
        p.wire +
        "\", " +
        p.field +
        ".toString());",
      )
      out.push("        }")
    } else {
      out.push(
        "        headers.put(\"" + p.wire + "\", " + p.field + ".toString());",
      )
    }
  }
  let body = if op.has_body {
    out.push("        headers.put(\"content-type\", \"application/json\");")
    "codec.encode(body)"
  } else {
    "null"
  }
  out.push(
    "        RawResponse res = transport.send(\"" +
    op.verb +
    "\", url, headers, " +
    body +
    ");",
  )
  out.push("        if (!res.ok()) {")
  out.push("            throw new ApiException(res.status, res.body);")
  out.push("        }")
  if op.resp != "" {
    out.push("        return " + op.resp + ".fromWire(codec.decode(res.body));")
  }
  out.push("    }")
  if optional_names.length() > 0 {
    let short = if op.resp == "" { "void" } else { op.resp }
    let call_args : Array[String] = []
    for n in short_names {
      call_args.push(n)
    }
    for _n in optional_names {
      call_args.push("null")
    }
    out.push("")
    out.push(
      "    public " +
      short +
      " " +
      op.handler +
      "(" +
      short_decls.join(", ") +
      ") {",
    )
    out.push(
      "        " +
      (if op.resp == "" { "" } else { "return " }) +
      op.handler +
      "(" +
      call_args.join(", ") +
      ");",
    )
    out.push("    }")
  }
  out.push("")
  out
}

///|
/// The whole file. The nested types come first, because a Java method cannot
/// mention a class the compiler has not met yet in a more readable order than the
/// one a reader needs: error, ports, models, calls.
fn emit_java(m : Model) -> String {
  let out : Array[String] = []
  out.push(
    "// Code generated by `mctl api java` from a `.api` spec. DO NOT EDIT.",
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
    "// Java allows one public type per file, so everything lives inside",
  )
  out.push(
    "// `" +
    m.class_name +
    "`: `" +
    m.class_name +
    ".Transport` sends a request,",
  )
  out.push(
    "// `" +
    m.class_name +
    ".Codec` turns a value into JSON and back (back it with",
  )
  out.push("// Jackson or Gson), and a model is `" + m.class_name + ".User`.")
  out.push("")
  out.push("import java.net.URLEncoder;")
  out.push("import java.nio.charset.StandardCharsets;")
  out.push("import java.util.ArrayList;")
  out.push("import java.util.LinkedHashMap;")
  out.push("import java.util.List;")
  out.push("import java.util.Map;")
  out.push("")
  out.push("public final class " + m.class_name + " {")
  out.push("    /** An answer the service did not send with a 2xx status. */")
  out.push(
    "    public static final class ApiException extends RuntimeException {",
  )
  out.push("        private static final long serialVersionUID = 1L;")
  out.push("")
  out.push("        public final int status;")
  out.push("        public final String body;")
  out.push("")
  out.push("        public ApiException(int status, String body) {")
  out.push("            super(\"HTTP \" + status);")
  out.push("            this.status = status;")
  out.push("            this.body = body;")
  out.push("        }")
  out.push("    }")
  out.push("")
  out.push("    /** One raw answer: the status and the text of the body. */")
  out.push("    public static final class RawResponse {")
  out.push("        public final int status;")
  out.push("        public final String body;")
  out.push("")
  out.push("        public RawResponse(int status, String body) {")
  out.push("            this.status = status;")
  out.push("            this.body = body;")
  out.push("        }")
  out.push("")
  out.push("        public boolean ok() {")
  out.push("            return status >= 200 && status < 300;")
  out.push("        }")
  out.push("    }")
  out.push("")
  out.push(
    "    /** The transport port: send one request, get the raw answer back. */",
  )
  out.push("    public interface Transport {")
  out.push(
    "        RawResponse send(String method, String url, Map<String, String> headers, String body);",
  )
  out.push("    }")
  out.push("")
  out.push("    /** The JSON port: encode a value, decode an object. */")
  out.push("    public interface Codec {")
  out.push("        String encode(Object value);")
  out.push("")
  out.push("        Map<String, Object> decode(String text);")
  out.push("    }")
  out.push("")
  for t in m.types {
    for line in java_type(t, m.types) {
      out.push(line)
    }
  }
  out.push("    private final String baseUrl;")
  out.push("    private final Transport transport;")
  out.push("    private final Codec codec;")
  out.push("    /** Bearer token sent with every request while set. */")
  out.push("    public String token;")
  out.push("")
  out.push(
    "    public " +
    m.class_name +
    "(String baseUrl, Transport transport, Codec codec) {",
  )
  out.push("        this.baseUrl = baseUrl.replaceAll(\"/+$\", \"\");")
  out.push("        this.transport = transport;")
  out.push("        this.codec = codec;")
  out.push("    }")
  out.push("")
  out.push(
    "    /** A list out of the codec, or an empty one when the field was absent. */",
  )
  out.push("    @SuppressWarnings(\"unchecked\")")
  out.push("    static List<Object> asList(Object value) {")
  out.push("        return value == null ? List.of() : (List<Object>) value;")
  out.push("    }")
  out.push("")
  out.push(
    "    /** A map out of the codec, or an empty one when the field was absent. */",
  )
  out.push("    @SuppressWarnings(\"unchecked\")")
  out.push("    static Map<String, Object> asMap(Object value) {")
  out.push(
    "        return value == null ? Map.of() : (Map<String, Object>) value;",
  )
  out.push("    }")
  out.push("")
  out.push("    /** One URL segment, escaped for a path or a query string. */")
  out.push("    static String enc(Object value) {")
  out.push(
    "        return URLEncoder.encode(String.valueOf(value), StandardCharsets.UTF_8)",
  )
  out.push("                .replace(\"+\", \"%20\");")
  out.push("    }")
  out.push("")
  for op in m.ops {
    for line in java_method(op) {
      out.push(line)
    }
  }
  out.push("}")
  @text.join_lines(out)
}
