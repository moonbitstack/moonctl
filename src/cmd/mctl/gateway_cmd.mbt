// `mctl gateway` — an HTTP front door for a `.proto`, the half of goctl's gateway
// that turns routes into an app.

///|
/// `mctl gateway <file.proto>` — the gateway for the proto, written beside it:
/// `<stem>_gateway.mbt`. Routes come from a sibling `<stem>.routes` mapping file
/// when there is one (`VERB /path /package.Service/Method` per line), and from the
/// gRPC paths themselves when there is not — so a gateway can be generated before
/// the URLs are decided, and rewritten when they are.
async fn gateway(input : String) -> Unit {
  try {
    let proto = @moonctl.parse_proto(@fs.read_file(input).text())
    let map_path = replace_ext(input, ".proto", ".routes")
    let (routes, skipped) = if @fs.exists(map_path) {
      @moonctl.parse_route_map(proto, @fs.read_file(map_path).text())
    } else {
      (@moonctl.default_routes(proto), [])
    }
    for line in skipped {
      println("mctl: skipped route (no such method): " + line)
    }
    if routes.length() == 0 {
      println("mctl: no route to generate for " + input)
      return
    }
    let out = dir_of(input) + @moonctl.gateway_file_name(input)
    @fs.write_file(
      out,
      @moonctl.generate_gateway(proto, routes),
      create_mode=CreateOrTruncate,
    )
    println(
      "mctl: generated " +
      out +
      " from " +
      input +
      " (" +
      routes.length().to_string() +
      " route(s))",
    )
  } catch {
    e =>
      println(
        "mctl: cannot generate a gateway for " + input + ": " + e.to_string(),
      )
  }
}
