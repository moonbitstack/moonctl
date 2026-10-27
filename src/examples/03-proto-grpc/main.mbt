///|
/// The `.proto` front end → moonrpc. `parse_proto` reads a proto3 file — messages
/// (with `repeated`, `map<K,V>`, `oneof`, and `reserved`), enums, and a service
/// whose RPCs may be client/server `stream`ing — and `generate_grpc` emits for
/// moonrpc a struct per message with `encode` and `decode`, a `@moonrpc.Method` per
/// RPC, and per service a record of handlers whose `handlers()` is ready for
/// `GrpcServer`. `proto_reserved_conflicts` surfaces a field that illegally reuses a
/// `reserved` number or name.
///
///     moon run src/examples/03-proto-grpc
#coverage.skip
fn main {
  let source =
    #|syntax = "proto3";
    #|package shop;
    #|
    #|// order lifecycle
    #|enum Status {
    #|  UNKNOWN = 0;
    #|  PAID    = 1;
    #|  SHIPPED = 2;
    #|}
    #|
    #|message Item {
    #|  string sku = 1;
    #|  int64  qty = 2;
    #|}
    #|
    #|message Order {
    #|  reserved 3, 4;
    #|  reserved "legacy_note";
    #|  string              id     = 1;
    #|  repeated Item       items  = 2;
    #|  map<string, string> labels = 5;
    #|  Status              status = 6;
    #|  string              legacy_note = 9;
    #|  oneof contact {
    #|    string email = 7;
    #|    string phone = 8;
    #|  }
    #|}
    #|
    #|message Ack { bool ok = 1; }
    #|
    #|service Orders {
    #|  rpc Create (Order)        returns (Ack);
    #|  rpc Watch  (Order)        returns (stream Order);
    #|  rpc Upload (stream Item)  returns (Ack);
    #|}
  let proto = @moonctl.parse_proto(source)
  println(
    "package \{proto.package_}: \{proto.messages.length()} messages, \{proto.enums.length()} enums, \{proto.services.length()} services",
  )
  for m in proto.messages {
    let conflicts = @moonctl.proto_reserved_conflicts(m)
    if conflicts.length() > 0 {
      println("  reserved conflict in \{m.name}: \{conflicts.join(", ")}")
    }
  }
  println(
    "\n==== generate_grpc(parse_proto(src)) -> moonrpc messages and handlers ====\n",
  )
  println(@moonctl.generate_grpc(proto))
}
