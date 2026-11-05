// `gen mcp <file.api>`: the spec's routes as an MCP server.
//
// A tool is an annotated function — `#mcp.tool(description=…)` — and moonmcp derives
// the JSON input schema from its parameters, so the generator writes the functions
// and the registration a first build is going to rebuild anyway. The request type a
// route declares becomes the tool's arguments: a client supplies the same values an
// HTTP caller would put in the body, the query string or the path.
//
// The function bodies are the route's `TODO`: moonctl does not know what the tool
// should answer, and a stub that made something up would be worse than one that says
// so.

///|
/// The JSON schema type of a MoonBit type — `string`, `integer`, `number`, `boolean`
/// or an array of one — or `None` when the type has no schema of its own and is
/// carried as JSON text instead.
fn mcp_json_type(ty : String) -> String? {
  if @text.ends_with(ty, "?") {
    return mcp_json_type(ty[0:ty.length() - 1].to_owned())
  }
  if @text.starts_with(ty, "Array[") {
    let inner = ty[6:ty.length() - 1].to_owned()
    return match mcp_json_type(inner) {
      Some(t) => Some("array:" + t)
      None => None
    }
  }
  match ty {
    "String" => Some("string")
    "Bool" => Some("boolean")
    "Int32" | "Int64" | "UInt32" | "UInt64" | "Byte" => Some("integer")
    "Double" | "Float" => Some("number")
    "Bytes" => Some("string")
    _ => None
  }
}

///|
/// The `{ "type": … }` a property of the input schema carries.
fn mcp_schema_of(ty : String) -> String {
  match mcp_json_type(ty) {
    Some(t) =>
      if @text.starts_with(t, "array:") {
        "{\"type\": \"array\", \"items\": {\"type\": \"" +
        t[6:].to_owned() +
        "\"}}"
      } else {
        "{ \"type\": \"" + t + "\" }"
      }
    None => "{ \"type\": \"string\", \"description\": \"JSON text\" }"
  }
}

///|
/// The parameters a tool takes, from the request type `req` (`req = ""` for a route
/// that declares none): `slot : ty` for a value the caller must send, `slot? : ty`
/// for one it may leave out.
fn mcp_params(spec : @api.Spec, req : String) -> Array[(String, String, Bool)] {
  let out : Array[(String, String, Bool)] = []
  if req == "" {
    return out
  }
  for t in spec.types {
    if t.name != req {
      continue
    }
    for f in @api.flat_fields(t, spec.types) {
      let ty = f.type_
      let optional = @text.ends_with(ty, "?")
      let base = if optional { ty[0:ty.length() - 1].to_owned() } else { ty }
      // the declared type travels through; a value with no schema of its own is a
      // `String` in the signature and JSON text in the schema
      out.push((f.mbt_name(), base, optional))
    }
  }
  out
}

///|
/// `s` as a MoonBit string literal, quotes and backslashes escaped.
fn str_lit(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else {
      out.write_string(s[i:i + 1].to_owned())
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// The tool's name: its handler, spelled the way a MoonBit function is.
fn mcp_tool_name(r : @api.Route) -> String {
  @text.to_snake(r.handler)
}

///|
/// The description a tool carries: the route's `@doc`, or the verb and path when the
/// spec gave none.
fn mcp_description(r : @api.Route) -> String {
  if r.summary != "" {
    r.summary
  } else {
    r.verb + " " + r.path
  }
}

///|
/// One `#mcp.tool` function: the route's request fields as parameters, and a body
/// that says the route is not wired to anything yet.
fn mcp_tool_fn(
  r : @api.Route,
  name : String,
  params : Array[(String, String, Bool)],
) -> String {
  let mut signature = ""
  if params.length() == 0 {
    signature = "pub fn " + name + "() -> String {\n"
  } else {
    signature = "pub fn " + name + "(\n"
    for p in params {
      signature = signature +
        "  " +
        p.0 +
        (if p.2 { "?" } else { "" }) +
        " : " +
        (if mcp_json_type(p.1) is None { "String" } else { p.1 }) +
        ",\n"
    }
    signature = signature + ") -> String {\n"
  }
  // The parameters keep their names — a tool's input schema is derived from them —
  // and the stub body acknowledges them, so a freshly generated server is free of
  // unused-parameter warnings.
  let slots : Array[String] = []
  for p in params {
    slots.push(p.0)
  }
  let body = if slots.length() == 0 {
    "  " + str_lit("TODO: " + r.handler) + "\n"
  } else {
    "  ignore((" +
    slots.join(", ") +
    "))\n  " +
    str_lit("TODO: " + r.handler) +
    "\n"
  }
  "///|\n/// `" +
  r.verb +
  " " +
  r.path +
  "` — the tool `" +
  name +
  "`.\n#mcp.tool(description=" +
  str_lit(mcp_description(r)) +
  ")\n" +
  signature +
  body +
  "}\n\n"
}

///|
/// The `mcp.tool(…)` call that registers one tool: the arguments moonmcp decodes,
/// the schema they describe, and the description.
fn mcp_tool_call(
  r : @api.Route,
  name : String,
  params : Array[(String, String, Bool)],
) -> String {
  let mut args = ""
  let mut props = ""
  let required : Array[String] = []
  for p in params {
    args = args +
      (if p.2 {
        "      " +
        p.0 +
        "?=@moonmcp.decode_option(args, " +
        str_lit(p.0) +
        "),\n"
      } else {
        "      @moonmcp.decode(args, " + str_lit(p.0) + "),\n"
      })
    props = props +
      "        " +
      str_lit(p.0) +
      ": " +
      mcp_schema_of(p.1) +
      ",\n"
    if p.2 == false {
      required.push(str_lit(p.0))
    }
  }
  let call = if params.length() == 0 {
    "_args => ToJson::to_json(" + name + "())"
  } else {
    "args => ToJson::to_json(" + name + "(\n" + args + "    ))"
  }
  let schema = "{ \"type\": \"object\", \"properties\": {\n" +
    props +
    "      }" +
    (if required.length() == 0 {
      ""
    } else {
      ",\n      \"required\": [" + required.join(", ") + "]"
    }) +
    "\n    }"
  "  mcp.tool(\n    " +
  str_lit(name) +
  ",\n    " +
  call +
  ",\n    input_schema=" +
  schema +
  ",\n    description=" +
  str_lit(mcp_description(r)) +
  ",\n  )\n"
}

///|
/// The routes a tool is offered for, each with the name it is registered under: a
/// route whose request type declares no field would be a tool a client can call with
/// nothing to send, and moonmcp's own registration for it carries an unused-argument
/// warning, so those routes stay HTTP-only and are reported instead.
fn mcp_offered(
  spec : @api.Spec,
) -> Array[(@api.Route, String, Array[(String, String, Bool)])] {
  let out : Array[(@api.Route, String, Array[(String, String, Bool)])] = []
  let taken : Array[String] = []
  for r in spec.routes {
    let params = mcp_params(spec, r.req)
    if params.length() == 0 {
      continue
    }
    let base = mcp_tool_name(r)
    let mut name = base
    let mut n = 2
    while taken.contains(name) {
      name = base + "_" + n.to_string()
      n = n + 1
    }
    taken.push(name)
    out.push((r, name, params))
  }
  out
}

///|
/// The routes a generated server does not offer, each as `<verb> <path>`: they
/// declare no request type, so there is nothing for a tool to take.
pub fn mcp_skipped(spec : @api.Spec) -> Array[String] {
  let out : Array[String] = []
  for r in spec.routes {
    if mcp_params(spec, r.req).length() == 0 {
      out.push(r.verb + " " + r.path)
    }
  }
  out
}

///|
/// `internal/tools/tools.mbt` for `spec`: one annotated function per offered route.
pub fn mcp_tools_for(spec : @api.Spec) -> String {
  let offered = mcp_offered(spec)
  let mut out = "///|\n/// The tools of the " +
    spec.service +
    " server: one per route, its parameters the route's request type.\n/// Each annotated function is offered by the server; its parameters become the\n/// tool's input schema. Edit freely: `tools.g.mbt` is regenerated on build.\n"
  for entry in offered {
    out = out + "\n" + mcp_tool_fn(entry.0, entry.1, entry.2)
  }
  out
}

///|
/// `internal/tools/tools.g.mbt`: what moonmcp regenerates from those functions, so a
/// fresh project compiles before its first build.
pub fn mcp_registration_for(spec : @api.Spec) -> String {
  let offered = mcp_offered(spec)
  let mut out = "// Generated by moonmcp from tools.mbt. Edit those files, not this one.\n\n///|\npub fn register(mcp : @moonmcp.Server) -> Unit {\n"
  for entry in offered {
    out = out + mcp_tool_call(entry.0, entry.1, entry.2)
  }
  out + "}\n"
}

///|
/// The test a spec-derived server is seeded with: every offered route registered as a
/// tool, counted through `tools/list`.
pub fn mcp_checks_for(spec : @api.Spec) -> String {
  let n = mcp_offered(spec).length().to_string()
  let src =
    #|///|
    #|async test "every route with a request type is a tool" {
    #|  let mcp = @moonmcp.Server::new("test")
    #|  @tools.register(mcp)
    #|  let call : Json = {
    #|    "jsonrpc": "2.0",
    #|    "id": 1,
    #|    "method": "tools/list",
    #|    "params": {
    #|      "_meta": {
    #|        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    #|        "io.modelcontextprotocol/clientCapabilities": {},
    #|      },
    #|    },
    #|  }
    #|  guard mcp.handle(call)
    #|    is Some({ "result": { "tools": Array(list), .. }, .. }) else {
    #|    fail("no tools in the reply")
    #|  }
    #|  assert_eq(list.length(), %n)
    #|}
  src.replace_all(old="%n", new=n)
}

///|
/// The MCP server tree for the service `spec` describes: the same module, packages
/// and build rule as `generate_mcp_tree`, with the spec's routes as its tools.
pub fn generate_mcp_from_spec(
  spec : @api.Spec,
  style? : @style.Style,
  dir~ : String = "",
) -> Array[TreeFile] {
  generate_mcp_tree(
    spec.service,
    style?,
    dir~,
    tools=mcp_tools_for(spec),
    registration=mcp_registration_for(spec),
    checks=mcp_checks_for(spec),
  )
}
