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
      out, "{ verb: \"POST\", path: \"/v1/users\", rpc: \"/demo.UserService/Create\" }",
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
