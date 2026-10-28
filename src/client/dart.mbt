// The Dart emitter (goctl leaves Dart to plugins). One class per `type` block with
// `fromJson` / `toJson`, one `Future`-returning method per route. Transport is a
// `Send` port, so the file imports only `dart:convert` and a generated client
// compiles with `dart analyze` without a single `pubspec.yaml` dependency.
//
// Everything Dart-side is written with single quotes, which MoonBit's double-quoted
// strings carry unchanged — only `"` would need escaping, and none is used.

///|
/// The Dart type a MoonBit one maps to.
fn dart_ty(ty : Ty) -> String {
  match ty {
    Opt(t) => dart_ty(t) + "?"
    List(t) => "List<" + dart_ty(t) + ">"
    Dict(k, v) =>
      match k {
        Named(n) =>
          "Map<" +
          (if n == "String" { "String" } else { "int" }) +
          ", " +
          dart_ty(v) +
          ">"
        _ => "Map<String, " + dart_ty(v) + ">"
      }
    Named(n) =>
      match n {
        "String" | "Bytes" => "String"
        "Bool" => "bool"
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" => "int"
        "Int64" | "UInt64" => "int"
        "Float" | "Double" => "double"
        "Json" | "Unit" => "dynamic"
        _ => pascal(n)
      }
  }
}

///|
/// The expression that reads `expr` — a `dynamic` out of `jsonDecode` — as the
/// value of `ty`, casting through `num` where Dart separates the numeric types and
/// recursing into lists and maps.
fn dart_decode(ty : Ty, expr : String) -> String {
  match ty {
    Opt(t) => "(" + expr + " == null ? null : " + dart_decode(t, expr) + ")"
    List(t) =>
      "(" +
      expr +
      " as List<dynamic>).map((e) => " +
      dart_decode(t, "e") +
      ").toList()"
    Dict(_, v) =>
      "(" +
      expr +
      " as Map<String, dynamic>).map((k, e) => MapEntry(k, " +
      dart_decode(v, "e") +
      "))"
    Named(n) =>
      match n {
        "String" | "Bytes" => expr + " as String"
        "Bool" => expr + " as bool"
        "Int" | "Int32" | "UInt" | "UInt32" | "Byte" =>
          "(" + expr + " as num).toInt()"
        "Int64" | "UInt64" => "(" + expr + " as num).toInt()"
        "Float" | "Double" => "(" + expr + " as num).toDouble()"
        "Json" | "Unit" => expr
        _ => pascal(n) + ".fromJson(" + expr + " as Map<String, dynamic>)"
      }
  }
}

///|
/// The expression that makes `expr` JSON-encodable: a model goes through its
/// `toJson`, and only the types that actually hold one are walked.
fn dart_encode(ty : Ty, expr : String) -> String {
  match ty {
    Opt(t) =>
      match t {
        List(e) =>
          if mentions_named(e) {
            expr + "?.map((e) => " + dart_encode(e, "e") + ").toList()"
          } else {
            expr
          }
        Dict(_, v) =>
          if mentions_named(v) {
            expr + "?.map((k, e) => MapEntry(k, " + dart_encode(v, "e") + "))"
          } else {
            expr
          }
        Named(n) => if is_scalar(n) { expr } else { expr + "?.toJson()" }
        _ => expr
      }
    List(t) =>
      if mentions_named(t) {
        expr + ".map((e) => " + dart_encode(t, "e") + ").toList()"
      } else {
        expr
      }
    Dict(_, v) =>
      if mentions_named(v) {
        expr + ".map((k, e) => MapEntry(k, " + dart_encode(v, "e") + "))"
      } else {
        expr
      }
    Named(n) => if is_scalar(n) { expr } else { expr + ".toJson()" }
  }
}

///|
/// One model class: its fields, a constructor naming every one of them, and the
/// pair of methods that move it across the wire.
fn dart_type(t : @api.TypeDef, types : Array[@api.TypeDef]) -> Array[String] {
  let out : Array[String] = []
  let name = pascal(t.name)
  let fields = @api.flat_fields(t, types)
  out.push("/// One `" + t.name + "` of the spec.")
  out.push("class " + name + " {")
  for f in fields {
    out.push(
      "  final " + dart_ty(field_ty(f)) + " " + camel(f.json_name()) + ";",
    )
  }
  out.push("")
  out.push("  const " + name + "({")
  for f in fields {
    out.push(
      "    " +
      (if is_nullable(field_ty(f)) { "" } else { "required " }) +
      "this." +
      camel(f.json_name()) +
      ",",
    )
  }
  out.push("  });")
  out.push("")
  out.push("  factory " + name + ".fromJson(Map<String, dynamic> j) {")
  out.push("    return " + name + "(")
  for f in fields {
    out.push(
      "      " +
      camel(f.json_name()) +
      ": " +
      dart_decode(field_ty(f), "j['" + f.json_name() + "']") +
      ",",
    )
  }
  out.push("    );")
  out.push("  }")
  out.push("")
  out.push("  Map<String, dynamic> toJson() {")
  out.push("    final m = <String, dynamic>{};")
  for f in fields {
    out.push(
      "    m['" +
      f.json_name() +
      "'] = " +
      dart_encode(field_ty(f), camel(f.json_name())) +
      ";",
    )
  }
  out.push("    return m;")
  out.push("  }")
  out.push("}")
  out.push("")
  out
}

///|
/// The path a method requests, as one Dart string with `${…}` where a `:seg` was.
fn dart_path(op : Op) -> String {
  let mut out = "'"
  for seg in @text.path_segments(op.path) {
    if seg.length() > 0 && seg[0] == ':' {
      out = out +
        "/" +
        interp_open() +
        path_value(Dart, camel(seg[1:].to_owned())) +
        "}"
    } else {
      out = out + "/" + seg
    }
  }
  if out == "'" {
    out = "'/"
  }
  out + "'"
}

///|
/// One route as one method. Every parameter but the body is named, which is what
/// Dart style asks for once a call carries more than two arguments.
fn dart_method(op : Op) -> Array[String] {
  let out : Array[String] = []
  let positional : Array[String] = []
  let named : Array[String] = []
  for (name, ty, required) in ordered_params(op) {
    if name == "body" {
      positional.push(op.req + " body")
    } else {
      named.push(
        (if required { "required " } else { "" }) +
        dart_ty(if required { parse_ty(ty) } else { opt_of(parse_ty(ty)) }) +
        " " +
        name,
      )
    }
  }
  let ret = if op.resp == "" { "void" } else { op.resp }
  let sig = if named.length() > 0 {
    positional.join(", ") +
    (if positional.length() > 0 { ", " } else { "" }) +
    "{" +
    named.join(", ") +
    "}"
  } else {
    positional.join(", ")
  }
  if op.summary != "" {
    out.push("  /// " + op.summary)
  }
  out.push("  Future<" + ret + "> " + op.handler + "(" + sig + ") async {")
  out.push("    final path = " + dart_path(op) + ";")
  if op.query_params.length() > 0 {
    out.push("    final query = <String>[];")
    for p in op.query_params {
      out.push(
        "    " +
        (if p.optional { "if (" + p.field + " != null) {" } else { "{" }),
      )
      out.push(
        "      query.add('" +
        p.wire +
        "=" +
        interp_open() +
        path_value(Dart, p.field) +
        "}');",
      )
      out.push("    }")
    }
    out.push(
      "    final qs = query.isEmpty ? '' : '?" +
      interp_open() +
      "query.join('&')}';",
    )
    out.push("    final url = Uri.parse('$baseUrl$path$qs');")
  } else {
    out.push("    final url = Uri.parse('$baseUrl$path');")
  }
  out.push(
    "    final headers = <String, String>{'accept': 'application/json'};",
  )
  out.push("    if (token != null) {")
  out.push("      headers['authorization'] = 'Bearer $token';")
  out.push("    }")
  for p in op.header_params {
    if p.optional {
      out.push("    if (" + p.field + " != null) {")
      out.push("      headers['" + p.wire + "'] = " + p.field + ".toString();")
      out.push("    }")
    } else {
      out.push("    headers['" + p.wire + "'] = " + p.field + ".toString();")
    }
  }
  let body = if op.has_body {
    out.push("    headers['content-type'] = 'application/json';")
    "jsonEncode(body.toJson())"
  } else {
    "null"
  }
  out.push(
    "    final res = await send('" + op.verb + "', url, headers, " + body + ");",
  )
  out.push("    if (!res.ok) {")
  out.push("      throw ApiException(res.status, res.body);")
  out.push("    }")
  if op.resp != "" {
    out.push(
      "    return " +
      op.resp +
      ".fromJson(jsonDecode(res.body) as Map<String, dynamic>);",
    )
  }
  out.push("  }")
  out.push("")
  out
}

///|
/// The whole file: the exception, the transport port, the models, then the client.
fn emit_dart(m : Model) -> String {
  let out : Array[String] = []
  out.push(
    "// Code generated by `mctl api dart` from a `.api` spec. DO NOT EDIT.",
  )
  out.push("//")
  out.push(
    "// " +
    m.service +
    " — a typed client for the MoonAPI routes of the spec.",
  )
  out.push("//")
  out.push(
    "// One route is one method: `path:` fields become named parameters, `form:`",
  )
  out.push(
    "// fields become query parameters, `header:` fields become headers, and the",
  )
  out.push("// `json:` fields of the request type become the body.")
  out.push("//")
  out.push(
    "// The transport is a `Send` port, so this file needs `dart:convert` and",
  )
  out.push(
    "// nothing else: hand it `package:http`, `dart:io` or a test double.",
  )
  out.push("")
  out.push("import 'dart:convert';")
  out.push("")
  out.push("/// An answer the service did not send with a 2xx status.")
  out.push("class ApiException implements Exception {")
  out.push("  ApiException(this.status, this.body);")
  out.push("")
  out.push("  final int status;")
  out.push("  final String body;")
  out.push("")
  out.push("  @override")
  out.push("  String toString() => 'ApiException($status): $body';")
  out.push("}")
  out.push("")
  out.push("/// One raw answer: the status and the text of the body.")
  out.push("class RawResponse {")
  out.push("  const RawResponse(this.status, this.body);")
  out.push("")
  out.push("  final int status;")
  out.push("  final String body;")
  out.push("")
  out.push("  bool get ok => status >= 200 && status < 300;")
  out.push("}")
  out.push("")
  out.push("/// The transport port: send one request, get the raw answer back.")
  out.push("typedef Send = Future<RawResponse> Function(")
  out.push("  String method,")
  out.push("  Uri url,")
  out.push("  Map<String, String> headers,")
  out.push("  String? body,")
  out.push(");")
  out.push("")
  for t in m.types {
    for line in dart_type(t, m.types) {
      out.push(line)
    }
  }
  out.push("class " + m.class_name + " {")
  out.push(
    "  " +
    m.class_name +
    "({required String baseUrl, required this.send, this.token})",
  )
  out.push("      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');")
  out.push("")
  out.push("  /// Base URL of the service; a trailing slash is dropped.")
  out.push("  final String baseUrl;")
  out.push("  /// The transport every call goes through.")
  out.push("  final Send send;")
  out.push("  /// Bearer token sent with every request while set.")
  out.push("  final String? token;")
  out.push("")
  for op in m.ops {
    for line in dart_method(op) {
      out.push(line)
    }
  }
  out.push("}")
  @text.join_lines(out)
}
