///|
/// A proto shared by the tests below: two services, one plain RPC each, and a
/// streaming one that cannot sit behind an HTTP route.
fn gateway_proto_src() -> String {
  (
    #|syntax = "proto3";
    #|package demo;
    #|
    #|message CreateReq { string name = 1; }
    #|message User { string id = 1; }
    #|message Job { string id = 1; }
    #|
    #|service UserService {
    #|  rpc Create(CreateReq) returns (User);
    #|  rpc Watch(CreateReq) returns (stream User);
    #|}
    #|
    #|service JobService {
    #|  rpc Submit(Job) returns (Job);
    #|}
  )
}

///|
test "every unary rpc gets the gRPC path as its route" {
  let proto = parse_proto(gateway_proto_src())
  let routes = default_routes(proto)
  assert_eq(routes.length(), 2)
  assert_eq(routes[0].verb, "POST")
  // the package is dropped from the URL: one gateway fronts one package
  assert_eq(routes[0].path, "/UserService/Create")
  assert_eq(routes[0].rpc, "/demo.UserService/Create")
  assert_eq(routes[1].path, "/JobService/Submit")
  assert_eq(routes[1].rpc, "/demo.JobService/Submit")
}

///|
test "a streaming rpc has no route, and the file says so" {
  let proto = parse_proto(gateway_proto_src())
  let out = generate_gateway(proto, default_routes(proto))
  assert_eq(contains(out, "Streaming methods have no HTTP route:"), true)
  assert_eq(contains(out, "/demo.UserService/Watch"), true)
  // ... but it is not in the route table
  assert_eq(
    contains(out, "{ verb: \"POST\", path: \"/UserService/Watch\""),
    false,
  )
}

///|
test "a mapping file names the verb and the path" {
  let proto = parse_proto(gateway_proto_src())
  let map =
    #|# the public surface
    #|
    #|post   /v1/users        /demo.UserService/Create
    #|get    /v1/jobs         /demo.JobService/Submit
  let (routes, skipped) = parse_route_map(proto, map)
  assert_eq(routes.length(), 2)
  assert_eq(routes[0].verb, "POST")
  assert_eq(routes[0].path, "/v1/users")
  assert_eq(routes[0].rpc, "/demo.UserService/Create")
  // the verb is upper-cased, so a mapping file may spell it either way
  assert_eq(routes[1].verb, "GET")
  assert_eq(skipped.length(), 0)
  let out = generate_gateway(proto, routes)
  assert_eq(
    contains(
      out, "{ verb: \"POST\", path: \"/v1/users\", rpc: \"/demo.UserService/Create\", }",
    ),
    true,
  )
}

///|
test "a mapping line that names a method the proto does not have is skipped" {
  let proto = parse_proto(gateway_proto_src())
  let map =
    #|post /v1/users /demo.UserService/Create
    #|post /v1/ghost /demo.UserService/Ghost
    #|only two words
  let (routes, skipped) = parse_route_map(proto, map)
  assert_eq(routes.length(), 1)
  assert_eq(skipped.length(), 2)
  assert_eq(skipped[0], "post /v1/ghost /demo.UserService/Ghost")
}

///|
test "the gateway answers 200, 400, 404 and 502" {
  let proto = parse_proto(gateway_proto_src())
  let out = generate_gateway(proto, default_routes(proto))
  // the route table is the single source of truth for both the gateway and its
  // callers
  assert_eq(contains(out, "pub fn routes() -> Array[GatewayRoute] {"), true)
  assert_eq(contains(out, "pub(all) struct Caller {"), true)
  assert_eq(
    contains(out, "call : (String, Json) -> Json raise GatewayError"),
    true,
  )
  assert_eq(
    contains(out, "fn method_of(verb : String, path : String) -> String {"),
    true,
  )
  assert_eq(contains(out, "pub fn Gateway::handle("), true)
  assert_eq(contains(out, "pub fn Gateway::handle_text("), true)
  assert_eq(contains(out, "status: 404,"), true)
  assert_eq(contains(out, "status: 400,"), true)
  assert_eq(contains(out, "status: 502,"), true)
  assert_eq(contains(out, "status: 200, body: reply"), true)
}

///|
test "the file is named after the proto" {
  assert_eq(gateway_file_name("greet.proto"), "greet_gateway.mbt")
  assert_eq(
    gateway_file_name("proto/ShopService.proto"),
    "shop_service_gateway.mbt",
  )
  assert_eq(gateway_file_name(""), "gateway.mbt")
}

///|
test "a segment that starts with a colon is a parameter" {
  assert_eq(is_param(":id"), true)
  assert_eq(is_param("id"), false)
  assert_eq(is_param(":"), false)
  assert_eq(is_param(""), false)
  assert_eq(param_name(":userId"), "userId")
  assert_eq(param_name("userId"), "")
}

///|
test "a parameter and a literal are the same shape only when the literal is not one" {
  let by_param = {
    verb: "GET",
    path: "/v1/users/:id",
    rpc: "/shop.UserService/Get",
  }
  let by_other_name = {
    verb: "GET",
    path: "/v1/users/:name",
    rpc: "/shop.UserService/Get",
  }
  let by_literal = {
    verb: "GET",
    path: "/v1/users/me",
    rpc: "/shop.UserService/Get",
  }
  assert_eq(route_shape(by_param), "GET /v1/users/{}")
  assert_eq(route_shape(by_param), route_shape(by_other_name))
  assert_eq(route_shape(by_literal), "GET /v1/users/me")
  // the verb is part of the shape: one path can answer a GET and a POST
  let posted = {
    verb: "POST",
    path: "/v1/users/:id",
    rpc: "/shop.UserService/Update",
  }
  assert_eq(route_shape(posted) == route_shape(by_param), false)
  // the root is a shape of its own
  let root = { verb: "GET", path: "/", rpc: "/shop.UserService/Get", }
  assert_eq(route_shape(root), "GET /")
}

///|
test "two routes of one shape are reported, and only those" {
  let proto = parse_proto(gateway_proto_src())
  let map =
    #|get  /v1/users/:id    /demo.UserService/Create
    #|get  /v1/users/:name  /demo.UserService/Create
    #|get  /v1/users/me     /demo.UserService/Create
    #|post /v1/users/:id    /demo.JobService/Submit
  let (routes, skipped) = parse_route_map(proto, map)
  assert_eq(skipped.length(), 0)
  assert_eq(routes.length(), 4)
  let clashes = route_clashes(routes)
  assert_eq(clashes.length(), 1)
  assert_eq(
    clashes[0],
    "`GET /v1/users/:name` answers the same requests as `GET /v1/users/:id`",
  )
}

///|
test "a route map may name parameters, and one that cannot bind is skipped" {
  let proto = parse_proto(gateway_proto_src())
  let map =
    #|get  /v1/users/:id       /demo.UserService/Create
    #|get  /v1/jobs/:          /demo.JobService/Submit
    #|get  /v1/jobs/:a/:a      /demo.JobService/Submit
    #|get  v1/jobs             /demo.JobService/Submit
    #|get  /v1/jobs/:9lives    /demo.JobService/Submit
  let (routes, skipped) = parse_route_map(proto, map)
  assert_eq(routes.length(), 1)
  assert_eq(routes[0].path, "/v1/users/:id")
  assert_eq(skipped.length(), 4)
}

///|
test "the generated gateway carries the matcher and binds a parameter" {
  let proto = parse_proto(gateway_proto_src())
  let map =
    #|get /v1/users/:id /demo.UserService/Create
  let (routes, _) = parse_route_map(proto, map)
  let out = generate_gateway(proto, routes)
  assert_eq(out.contains("pub(all) struct GatewayMatch {"), true)
  assert_eq(
    out.contains(
      "fn match_route(verb : String, path : String) -> GatewayMatch?",
    ),
    true,
  )
  assert_eq(
    out.contains("pub fn method_of(verb : String, path : String) -> String {"),
    true,
  )
  assert_eq(out.contains("fn with_params("), true)
  assert_eq(out.contains("params[segment[1:].to_owned()] = parts[i]"), true)
  // a literal counts for more than a parameter, so the more specific route wins
  assert_eq(out.contains("if matched && weight > best_weight"), true)
  // the body a request arrives with is read by the family's parser, not by hand
  assert_eq(out.contains("@json.loads(body)"), true)
  assert_eq(out.contains("a path parameter needs a JSON object body"), true)
}
