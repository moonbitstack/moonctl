// `mctl gateway` (← goctl's `gateway`): an HTTP front door for a gRPC service.
//
// A gRPC service speaks `POST /package.Service/Method` with a protobuf body, which
// is a protocol, not a REST API: no browser speaks it, and no CDN caches it. A
// gateway is the translation layer — HTTP verbs and paths in front, gRPC behind —
// so that a `.proto` a team already has can be reached from a web page.
//
// The gateway here is the routing and the envelope, not the transport: a caller
// port takes the gRPC method's full path and the request document and returns the
// reply document, and everything above that port (the route table, the 400/404/502
// answers, the JSON bodies) is generated and typed. Binding the port to a real
// channel is a dozen lines, the same way the mongo port is.
//
// Routes come from a mapping file when there is one — `POST /v1/users
// demo.UserService/Create` per line — and from the gRPC path itself when there is
// not, so a gateway can be generated before anyone has decided on URLs.

///|
/// One HTTP route and the gRPC method behind it: the verb and path the gateway
/// answers, and the fully-qualified method it forwards to. A segment of `path` that
/// begins with `:` is a parameter — it stands for one segment of the request path,
/// and the value it took is bound into the request document under its name.
pub(all) struct GatewayRoute {
  verb : String
  path : String
  rpc : String
}

///|
/// The fully-qualified gRPC path of an RPC: `/package.Service/Method`, the spelling
/// a channel calls and a gateway forwards to.
fn rpc_path(pkg : String, service : String, rpc : String) -> String {
  let full = if pkg == "" { service } else { pkg + "." + service }
  "/" + full + "/" + rpc
}

///|
/// Whether an RPC can sit behind an HTTP route: a gRPC stream cannot, because an
/// HTTP response is one body with one end. A streaming RPC is left out of the route
/// table, and the generated file says which ones were left out.
fn is_streaming(r : Rpc) -> Bool {
  r.client_streaming || r.server_streaming
}

///|
/// Every RPC of `proto` as the default route: `POST /<Service>/<Method>` — the gRPC
/// path with its package dropped, because a gateway in front of one package does not
/// need the package repeated in the URL. A `POST` is the method gRPC itself uses, so
/// the mapping is the one that always works.
pub fn default_routes(proto : Proto) -> Array[GatewayRoute] {
  let out : Array[GatewayRoute] = []
  for s in proto.services {
    for r in s.rpcs {
      if is_streaming(r) {
        continue
      }
      out.push({
        verb: "POST",
        path: "/" + s.name + "/" + r.name,
        rpc: rpc_path(proto.package_, s.name, r.name),
      })
    }
  }
  out
}

///|
/// Whether `proto` declares the gRPC method `target` (`/package.Service/Method`), so a
/// hand-written route that names a method the spec does not have is caught here
/// rather than at the first request.
pub fn has_method(proto : Proto, target : String) -> Bool {
  for s in proto.services {
    for r in s.rpcs {
      if rpc_path(proto.package_, s.name, r.name) == target {
        return true
      }
    }
  }
  false
}

///|
/// Whether a path segment is a parameter: a `:` and a name after it.
pub fn is_param(segment : String) -> Bool {
  segment.length() > 1 && segment[0] == ':'
}

///|
/// The name a parameter segment binds to (`:userId` → `userId`), or `""` when the
/// segment is not a parameter.
pub fn param_name(segment : String) -> String {
  if is_param(segment) {
    segment[1:].to_owned()
  } else {
    ""
  }
}

///|
/// Whether a name can be a member of a JSON request document: a letter or an
/// underscore, then letters, digits and underscores. A name the generated document
/// cannot carry is refused here rather than at the first request.
fn is_param_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for i = 0; i < name.length(); i = i + 1 {
    let c = name[i]
    let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    let digit = c >= '0' && c <= '9'
    if letter || digit || c == '_' {
      // a digit may not open a name, since a generated document reads it as a field
      if i == 0 && digit {
        return false
      }
      continue
    }
    return false
  }
  true
}

///|
/// What is wrong with a route path, or `""` when nothing is: it has to be a path, a
/// parameter has to name something, and one path may not bind one name twice — the
/// second segment would overwrite the first in the request document.
fn path_problem(path : String) -> String {
  if path == "" || path[0] != '/' {
    return "the path has to begin with /"
  }
  let seen : Array[String] = []
  for segment in @text.path_segments(path) {
    if segment.length() == 0 || segment[0] != ':' {
      continue
    }
    let name = param_name(segment)
    if is_param_name(name) == false {
      return "`" + segment + "` is not a parameter name"
    }
    if seen.contains(name) {
      return "`:" + name + "` appears twice"
    }
    seen.push(name)
  }
  ""
}

///|
/// The shape of a route: its verb and its path with every parameter replaced by
/// `{}`. Two routes of one shape answer the same requests, so only the first can be
/// reached.
pub fn route_shape(route : GatewayRoute) -> String {
  let mut out = route.verb + " "
  let segments = @text.path_segments(route.path)
  for i = 0; i < segments.length(); i = i + 1 {
    out = out + "/" + (if is_param(segments[i]) { "{}" } else { segments[i] })
  }
  if segments.length() == 0 {
    out = out + "/"
  }
  out
}

///|
/// The routes of `routes` that no request can tell apart, one sentence each. A table
/// carrying one has a route nothing reaches, so `mctl gateway` refuses to write it
/// rather than generate a table whose last line is dead.
pub fn route_clashes(routes : Array[GatewayRoute]) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < routes.length(); i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      if route_shape(routes[i]) == route_shape(routes[j]) {
        out.push(
          "`" +
          routes[i].verb +
          " " +
          routes[i].path +
          "` answers the same requests as `" +
          routes[j].verb +
          " " +
          routes[j].path +
          "`",
        )
      }
    }
  }
  out
}

///|
/// The routes a mapping file declares, in the order it declares them. A line is
/// `VERB /path /package.Service/Method`; `#` starts a comment, and a blank line is
/// skipped. A line naming a method the `.proto` does not declare, one that streams,
/// or one whose path will not match anything is left out — `skipped` reports the
/// line itself, so the caller can say which.
pub fn parse_route_map(
  proto : Proto,
  source : String,
) -> (Array[GatewayRoute], Array[String]) {
  let out : Array[GatewayRoute] = []
  let skipped : Array[String] = []
  for raw in @text.split_char(source, '\n') {
    let mut line = @text.trim(raw)
    let hash = @text.index_of_str(line, "#")
    if hash >= 0 {
      line = @text.trim(line[0:hash].to_owned())
    }
    if line == "" {
      continue
    }
    let parts = @text.split_char(line, ' ')
    let words : Array[String] = []
    for p in parts {
      let w = @text.trim(p)
      if w != "" {
        words.push(w)
      }
    }
    if words.length() < 3 {
      skipped.push(line)
      continue
    }
    if has_method(proto, words[2]) == false {
      skipped.push(line)
      continue
    }
    if path_problem(words[1]) != "" {
      skipped.push(line)
      continue
    }
    out.push({ verb: words[0].to_upper(), path: words[1], rpc: words[2], })
  }
  (out, skipped)
}

///|
/// The prelude of a generated gateway: the error a request can end in, the reply it
/// produces, the caller port, and the two route records.
fn gateway_prelude() -> String {
  "// Code generated by moonctl. DO NOT EDIT.\n" +
  "//\n" +
  "// `mctl gateway`: an HTTP front door for this `.proto`. A request's JSON body is\n" +
  "// forwarded to the gRPC method its route names, and the reply is handed back as\n" +
  "// the response body. The transport is the `Caller` port: bind it to a channel and\n" +
  "// the gateway is live.\n" +
  "//\n" +
  "// This file needs `moonbitstack/moonjson` imported as `@json`.\n" +
  "\n" +
  "///|\n/// What a request can end in: a body that will not parse, a path no route answers,\n/// or an upstream call that failed.\npub(all) suberror GatewayError {\n  GatewayBadRequest(why~ : String)\n  GatewayNotFound(route~ : String)\n  GatewayUpstream(status~ : Int32, message~ : String)\n}\n" +
  "\n" +
  "///|\n/// One answer: the HTTP status and the JSON body it carries.\npub(all) struct GatewayReply {\n  status : Int32\n  body : Json\n}\n" +
  "\n" +
  "///|\n/// The upstream a gateway calls: the gRPC method's full path (`/package.Service/\n/// Method`) and the request document, in return for the reply document.\npub(all) struct Caller {\n  call : (String, Json) -> Json raise GatewayError\n}\n" +
  "\n" +
  "///|\n/// One route: the HTTP verb and path the gateway answers, and the gRPC method it\n/// forwards to. A segment of `path` that begins with `:` is a parameter: it stands\n/// for one segment of the request path, and the value it took is bound into the\n/// request document under the name after the colon.\npub(all) struct GatewayRoute {\n  verb : String\n  path : String\n  rpc : String\n}\n" +
  "\n" +
  "///|\n/// A route that answered: the gRPC method, and the value each parameter of the path\n/// took, by parameter name.\npub(all) struct GatewayMatch {\n  rpc : String\n  params : Map[String, String]\n}\n" +
  "\n" +
  "///|\n/// A JSON object with one `error` member: what a failed request answers with.\nfn error_body(message : String) -> Json {\n  let m : Map[String, Json] = Map([])\n  m[\"error\"] = ToJson::to_json(message)\n  ToJson::to_json(m)\n}\n" +
  "\n" +
  "///|\n/// The one-line spelling of a failure, which is what the `error` member carries.\nfn describe(e : GatewayError) -> String {\n  match e {\n    GatewayBadRequest(why~) => \"bad request: \" + why\n    GatewayNotFound(route~) => \"no route for \" + route\n    GatewayUpstream(status~, message~) =>\n      \"upstream \" + status.to_string() + \": \" + message\n  }\n}\n\n"
}

///|
/// The route table, as a function so the gateway and its callers read the same list.
fn emit_routes(routes : Array[GatewayRoute]) -> String {
  let lines : Array[String] = []
  for r in routes {
    lines.push(
      "    { verb: " +
      @text.quote(r.verb) +
      ", path: " +
      @text.quote(r.path) +
      ", rpc: " +
      @text.quote(r.rpc) +
      ", },",
    )
  }
  "///|\n/// Every route of the gateway, in the order the `.proto` (or the mapping file)\n/// declared them.\npub fn routes() -> Array[GatewayRoute] {\n  [" +
  (if lines.length() == 0 { "" } else { "\n" }) +
  @text.join_lines(lines) +
  (if lines.length() == 0 { "" } else { "\n  " }) +
  "]\n}\n\n"
}

///|
/// The matcher: the path split into segments, the lookup that prefers a literal
/// segment over a parameter, and the two ways to read the answer.
fn emit_router() -> String {
  "///|\n/// The segments of a path, empty ones dropped: `/v1/users/7` → `[\"v1\", \"users\",\n/// \"7\"]`. A doubled slash and a trailing one are therefore the same request as\n/// without them.\nfn segments(path : String) -> Array[String] {\n  let out : Array[String] = []\n  let mut from = 0\n  for i = 0; i <= path.length(); i = i + 1 {\n    if i == path.length() || path[i] == '/' {\n      if i > from {\n        out.push(path[from:i].to_owned())\n      }\n      from = i + 1\n    }\n  }\n  out\n}\n\n" +
  "///|\n/// The route that answers a verb and a path, or nothing. A literal segment counts\n/// for more than a parameter, so `get /v1/users/me` still answers\n/// `/v1/users/me` when `get /v1/users/:id` is declared first; between two routes of\n/// one weight the earlier one wins, and the generator refuses to write two of the\n/// same shape.\nfn match_route(verb : String, path : String) -> GatewayMatch? {\n  let parts = segments(path)\n  let mut best : GatewayMatch? = None\n  let mut best_weight = -1\n  for route in routes() {\n    if route.verb != verb {\n      continue\n    }\n    let pattern = segments(route.path)\n    if pattern.length() != parts.length() {\n      continue\n    }\n    let params : Map[String, String] = Map([])\n    let mut weight = 0\n    let mut matched = true\n    for i = 0; i < pattern.length(); i = i + 1 {\n      let segment = pattern[i]\n      if segment.length() > 1 && segment[0] == ':' {\n        params[segment[1:].to_owned()] = parts[i]\n      } else if segment == parts[i] {\n        weight = weight + 1\n      } else {\n        matched = false\n        break\n      }\n    }\n    if matched && weight > best_weight {\n      best_weight = weight\n      best = Some({ rpc: route.rpc, params, })\n    }\n  }\n  best\n}\n\n" +
  "///|\n/// The gRPC method a verb and path name, or `\"\"` when no route answers them.\npub fn method_of(verb : String, path : String) -> String {\n  match match_route(verb, path) {\n    Some(found) => found.rpc\n    None => \"\"\n  }\n}\n\n" +
  "///|\n/// The request document a route's parameters make: `body` with each parameter bound\n/// as a member, a parameter winning over the same member in the body, since the path\n/// is where the client said which resource it means. A route with no parameters\n/// forwards the body untouched; a parameter on a body that is not an object is an\n/// error, because there is nowhere to put it.\nfn with_params(\n  body : Json,\n  params : Map[String, String],\n) -> Result[Json, String] {\n  if params.length() == 0 {\n    return Ok(body)\n  }\n  let members = match body {\n    Object(members) => members\n    _ => return Err(\"a path parameter needs a JSON object body\")\n  }\n  let merged : Map[String, Json] = Map([])\n  for name, value in members {\n    merged[name] = value\n  }\n  for name, value in params {\n    merged[name] = ToJson::to_json(value)\n  }\n  Ok(ToJson::to_json(merged))\n}\n\n" +
  "///|\n/// Whether a body carries nothing at all: a request with no body, or one whose body\n/// is only whitespace.\nfn blank(body : String) -> Bool {\n  for i = 0; i < body.length(); i = i + 1 {\n    let c = body[i]\n    if c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' {\n      return false\n    }\n  }\n  true\n}\n\n"
}

///|
/// Generate the gateway for `proto` with `routes`: the route table, the matcher, the
/// gateway itself, and the two entry points — `handle`, which takes a JSON body
/// already parsed, and `handle_text`, which parses the body a request carried.
///
/// Status codes are the four an HTTP client cares about: `200` for a reply, `400`
/// for a body that is not JSON or a parameter that has no object to land in, `404`
/// for a path no route answers, and `502` for a call the upstream failed. A gRPC
/// status does not leak through: an HTTP client reads it where it is meaningful — in
/// the reply body.
pub fn generate_gateway(proto : Proto, routes : Array[GatewayRoute]) -> String {
  let mut out = gateway_prelude()
  out = out + emit_routes(routes)
  let streamed : Array[String] = []
  for s in proto.services {
    for r in s.rpcs {
      if is_streaming(r) {
        streamed.push(rpc_path(proto.package_, s.name, r.name))
      }
    }
  }
  if streamed.length() > 0 {
    out = out +
      "// Streaming methods have no HTTP route: " +
      @text.join_lines(streamed) +
      ".\n\n"
  }
  out = out + emit_router()
  out = out +
    "///|\n/// The gateway: the upstream it calls. Routes come from `routes()`.\npub(all) struct Gateway {\n  caller : Caller\n}\n\n" +
    "///|\n/// A gateway over `caller`.\npub fn Gateway::new(caller : Caller) -> Gateway {\n  { caller, }\n}\n\n" +
    "///|\n/// Answer one request: find the route, bind the path's parameters, forward the\n/// body, wrap the reply.\npub fn Gateway::handle(\n  self : Gateway,\n  verb : String,\n  path : String,\n  body : Json,\n) -> GatewayReply {\n  let found = match match_route(verb, path) {\n    Some(found) => found\n    None =>\n      return {\n        status: 404,\n        body: error_body(\"no route for \" + verb + \" \" + path),\n      }\n  }\n  let request = match with_params(body, found.params) {\n    Ok(request) => request\n    Err(why) => return { status: 400, body: error_body(why), }\n  }\n  let reply = (self.caller.call)(found.rpc, request) catch {\n    e => return { status: 502, body: error_body(describe(e)), }\n  }\n  { status: 200, body: reply, }\n}\n\n" +
    "///|\n/// Answer one request whose body arrived as text, which is what a server hands its\n/// handler. A body that is not JSON answers `400` rather than raising; a blank one\n/// is the empty document, which is what a `GET` with path parameters sends.\npub fn Gateway::handle_text(\n  self : Gateway,\n  verb : String,\n  path : String,\n  body : String,\n) -> GatewayReply {\n  if blank(body) {\n    return self.handle(verb, path, Json((Map([]) : Map[String, Json])))\n  }\n  let doc = @json.loads(body) catch {\n    _ => return { status: 400, body: error_body(\"body is not JSON\"), }\n  }\n  self.handle(verb, path, doc)\n}\n"
  out
}

///|
/// The file a gateway lands in: the `.proto`'s own name, without its directory and
/// without its extension — `proto/greet.proto` → `greet_gateway.mbt`. A `.proto` may
/// declare several services, so the file name comes from the file rather than from
/// one of them.
pub fn gateway_file_name(proto_path : String) -> String {
  let mut start = 0
  for i = 0; i < proto_path.length(); i = i + 1 {
    let c = proto_path[i]
    if c == '/' || c == '\\' {
      start = i + 1
    }
  }
  let mut stem = proto_path[start:].to_owned()
  if @text.ends_with(stem, ".proto") {
    stem = stem[0:stem.length() - 6].to_owned()
  }
  if stem == "" {
    return "gateway.mbt"
  }
  @text.to_snake(stem) + "_gateway.mbt"
}
