///|
/// `mctl gateway`: a `.proto` reachable over HTTP. Routes come from a mapping file
/// when there is one and from the gRPC paths themselves when there is not, and the
/// transport behind them is a single port, so the generated file compiles with no
/// gRPC dependency at all.
///
/// The proto below has the three cases a gateway has to answer for: a plain RPC, a
/// second one on another service, and a streaming RPC that cannot be a route.
///
///     moon run src/examples/16-gateway
#coverage.skip
fn main {
  let proto = @moonctl.parse_proto(
    (
      #|syntax = "proto3";
      #|package shop;
      #|
      #|message CreateReq { string name = 1; }
      #|message User { string id = 1; }
      #|
      #|service UserService {
      #|  rpc Create(CreateReq) returns (User);
      #|  rpc Get(CreateReq) returns (User);
      #|  rpc Watch(CreateReq) returns (stream User);
      #|}
      #|
      #|service StockService {
      #|  rpc Count(CreateReq) returns (User);
      #|}
    ),
  )
  // the default mapping: the gRPC path, with the package dropped
  println("---- default routes")
  for r in @moonctl.default_routes(proto) {
    println("  " + r.verb + " " + r.path + " -> " + r.rpc)
  }
  println("")
  // and the mapping a project writes once the URLs are decided
  println("---- mapped routes")
  let (routes, skipped) = @moonctl.parse_route_map(
    proto,
    (
      #|# what the browser sees        what the RPC is called
      #|post /v1/users                /shop.UserService/Create
      #|get  /v1/users/:id            /shop.UserService/Get
      #|get  /v1/stock                /shop.StockService/Count
      #|post /v1/ghost                /shop.UserService/Ghost
      #|get  /v1/jobs/:               /shop.StockService/Count
    ),
  )
  for r in routes {
    // the shape is the route with its parameters taken out: two routes of one shape
    // answer the same requests, and the generator refuses a table carrying both
    println(
      "  " +
      r.verb +
      " " +
      r.path +
      " -> " +
      r.rpc +
      "   (" +
      @moonctl.route_shape(r) +
      ")",
    )
  }
  println(
    "  skipped " +
    skipped.length().to_string() +
    " line(s), unreadable or naming no such method",
  )
  println("")
  // a table with two routes of one shape is a spec error, not a gateway
  let (clashing, _) = @moonctl.parse_route_map(
    proto,
    (
      #|get /v1/users/:id    /shop.UserService/Get
      #|get /v1/users/:name  /shop.UserService/Get
    ),
  )
  println("---- clashes")
  for clash in @moonctl.route_clashes(clashing) {
    println("  " + clash)
  }
  println("")
  let gw = @moonctl.generate_gateway(proto, routes)
  println("gateway: " + gw.length().to_string() + " bytes")
  println("file: " + @moonctl.gateway_file_name("proto/shop.proto"))
  println("")
  for
    anchor in [
      "pub fn routes() -> Array[GatewayRoute] {", "fn match_route(verb : String, path : String) -> GatewayMatch? {",
      "fn with_params(", "pub fn Gateway::handle(",
    ] {
    println("---- " + anchor)
    println(excerpt(gw, anchor, 10))
  }
  // the streaming RPC is not a route, and the file says which one was left out
  println("---- streaming")
  println(
    "  Watch is called out: " +
    (at_of(gw, "/shop.UserService/Watch") >= 0).to_string(),
  )
}

///|
/// The first index in `hay` where `needle` starts, or `-1`.
fn at_of(hay : String, needle : String) -> Int32 {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut same = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
    }
    if same {
      return i
    }
  }
  -1
}

///|
/// The `lines` lines of `text` that follow the first occurrence of `anchor`.
fn excerpt(text : String, anchor : String, lines : Int32) -> String {
  let at = at_of(text, anchor)
  if at < 0 {
    return anchor + ": not found"
  }
  let mut end = at
  let mut seen = 0
  while end < text.length() && seen < lines {
    if text[end] == '\n' {
      seen = seen + 1
    }
    end = end + 1
  }
  text[at:end].to_owned()
}
