///|
fn kit_proto() -> @proto.Proto {
  let src =
    #|syntax = "proto3";
    #|package shop.v1;
    #|message Item { string name = 1; }
    #|service Store {
    #|  rpc Get (Item) returns (Item);
    #|  rpc List (Item) returns (stream Item);
    #|  rpc Load (stream Item) returns (Item);
    #|  rpc Sync (stream Item) returns (stream Item);
    #|}
  @proto.parse_proto(src)
}

///|
test "a dotted package becomes the module name" {
  let tree = generate_rpc_tree(kit_proto())
  assert_eq(contains(tree_at(tree, "moon.mod"), "name = \"shop_v1\""), true)
  assert_eq(
    contains(tree_at(tree, "pb/moon.pkg"), "\"moonbitstack/moonrpc\""),
    true,
  )
}

///|
test "logic starts unimplemented, typed as each call kind" {
  let tree = generate_rpc_tree(kit_proto())
  let get = tree_at(tree, "internal/logic/getlogic.mbt")
  assert_eq(contains(get, "_req : @pb.Item,"), true)
  assert_eq(contains(get, "Err(Unimplemented)"), true)
  assert_eq(
    contains(
      tree_at(tree, "internal/logic/synclogic.mbt"),
      ") -> Result[Array[@pb.Item], @moonrpc.Status] {",
    ),
    true,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/logic/loadlogic.mbt"),
      "_req : Array[@pb.Item],",
    ),
    true,
  )
}

///|
test "the client has one typed call per rpc on the matching channel call" {
  let client = tree_at(
    generate_rpc_tree(kit_proto()),
    "client/shopv1client.mbt",
  )
  assert_eq(contains(client, "pub struct StoreClient {"), true)
  assert_eq(
    contains(client, "self.channel.unary(\"/shop.v1.Store/Get\", req.encode())"),
    true,
  )
  assert_eq(
    contains(client, "self.channel.server_streaming(\"/shop.v1.Store/List\""),
    true,
  )
  assert_eq(
    contains(client, "self.channel.client_streaming(\"/shop.v1.Store/Load\""),
    true,
  )
  assert_eq(contains(client, "self.channel.bidi(\"/shop.v1.Store/Sync\""), true)
  assert_eq(contains(client, "reply.messages.map(@pb.Item::decode)"), true)
}

///|
test "a second run rewrites pb, server and client and keeps the logic" {
  let tree = generate_rpc_tree(kit_proto())
  let written = tree_plan(tree, _ => true).map(f => f.path)
  assert_eq(written, [
    "pb/moon.pkg", "pb/shopv1_grpc.mbt", "internal/server/moon.pkg", "internal/server/shopv1server.mbt",
    "client/shopv1client.mbt",
  ])
}

///|
test "without a seeded test the client package imports nothing for tests" {
  let pkg = tree_at(generate_rpc_tree(kit_proto()), "client/moon.pkg")
  assert_eq(contains(pkg, "supported_targets = \"native\""), true)
  assert_eq(contains(pkg, "for \"test\""), false)
}
