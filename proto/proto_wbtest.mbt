///|
fn contains(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
test "parse a minimal .proto" {
  let src =
    #|syntax = "proto3";
    #|package greet;
    #|
    #|// the greeter service
    #|service Greeter {
    #|  rpc SayHello (HelloRequest) returns (HelloReply);
    #|  rpc LotsOfReplies (HelloRequest) returns (stream HelloReply);
    #|}
    #|
    #|message HelloRequest {
    #|  string name = 1;
    #|  int32  age  = 2;
    #|  repeated string tags = 3;
    #|}
    #|
    #|message HelloReply {
    #|  string message = 1;
    #|}
  let proto = parse_proto(src)
  assert_eq(proto.package_, "greet")
  assert_eq(proto.services.length(), 1)
  assert_eq(proto.messages.length(), 2)
  let svc = proto.services[0]
  assert_eq(svc.name, "Greeter")
  assert_eq(svc.rpcs.length(), 2)
  assert_eq(svc.rpcs[0].name, "SayHello")
  assert_eq(svc.rpcs[0].request, "HelloRequest")
  assert_eq(svc.rpcs[0].response, "HelloReply")
  assert_eq(svc.rpcs[0].server_streaming, false)
  assert_eq(svc.rpcs[1].name, "LotsOfReplies")
  assert_eq(svc.rpcs[1].server_streaming, true)
  let req = proto.messages[0]
  assert_eq(req.name, "HelloRequest")
  assert_eq(req.fields.length(), 3)
  assert_eq(req.fields[0].name, "name")
  assert_eq(req.fields[0].type_, "String")
  assert_eq(req.fields[0].number, 1)
  assert_eq(req.fields[1].type_, "Int")
  assert_eq(req.fields[1].number, 2)
  assert_eq(req.fields[2].type_, "Array[String]")
  assert_eq(req.fields[2].number, 3)
}

///|
test "parse proto map fields and client streaming" {
  let src =
    #|service Store {
    #|  rpc Upload (stream Chunk) returns (Ack);
    #|}
    #|message Chunk {
    #|  map<string, int64> meta = 1;
    #|  bytes data = 2;
    #|}
    #|message Ack { bool ok = 1; }
  let proto = parse_proto(src)
  assert_eq(proto.package_, "")
  assert_eq(proto.services[0].rpcs[0].client_streaming, true)
  assert_eq(proto.messages[0].fields[0].type_, "Map[String, Int64]")
  assert_eq(proto.messages[0].fields[1].type_, "Bytes")
  assert_eq(proto.messages[1].fields[0].type_, "Bool")
}

///|
test "generate moonrpc service stub" {
  let src =
    #|package greet;
    #|service Greeter {
    #|  rpc SayHello (HelloRequest) returns (HelloReply);
    #|}
    #|message HelloRequest { string name = 1; }
    #|message HelloReply { string message = 1; }
  let code = generate_grpc(parse_proto(src))
  assert_eq(contains(code, "DO NOT EDIT"), true)
  assert_eq(contains(code, "pub(all) struct HelloRequest {"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(
    contains(
      code, "pub let greeter_say_hello : @moonrpc.Method = { service: \"greet.Greeter\", name: \"SayHello\" }",
    ),
    true,
  )
  assert_eq(contains(code, "pub(all) struct GreeterServer {"), true)
  assert_eq(
    contains(
      code, "say_hello : (HelloRequest) -> Result[HelloReply, @moonrpc.Status]",
    ),
    true,
  )
  assert_eq(
    contains(code, "pub fn greeter_methods() -> Array[@moonrpc.Method] {"),
    true,
  )
  assert_eq(contains(code, "[greeter_say_hello]"), true)
  assert_eq(
    contains(
      code, "pub fn hello_request_field_numbers() -> Array[(String, Int)] {",
    ),
    true,
  )
  assert_eq(contains(code, "(\"name\", 1)"), true)
}

///|
test "parse a proto enum and generate a MoonBit enum with its int mapping" {
  let src =
    #|syntax = "proto3";
    #|package traffic;
    #|
    #|// a signal's phase
    #|enum Light {
    #|  LIGHT_UNKNOWN = 0;
    #|  RED = 1;
    #|  GREEN = 2;
    #|  YELLOW = 3;
    #|}
    #|message Signal { Light light = 1; }
  let proto = parse_proto(src)
  assert_eq(proto.enums.length(), 1)
  let en = proto.enums[0]
  assert_eq(en.name, "Light")
  assert_eq(en.values.length(), 4)
  assert_eq(en.values[0].name, "LIGHT_UNKNOWN")
  assert_eq(en.values[0].number, 0)
  assert_eq(en.values[2].name, "GREEN")
  assert_eq(en.values[2].number, 2)
  // an enum-typed message field passes the enum name through as its type
  assert_eq(proto.messages[0].fields[0].type_, "Light")
  let code = generate_grpc(proto)
  assert_eq(contains(code, "pub enum Light {"), true)
  assert_eq(contains(code, "  RED\n"), true)
  assert_eq(contains(code, "} derive(Eq, Debug)"), true)
  assert_eq(contains(code, "pub fn Light::to_int(self : Light) -> Int {"), true)
  assert_eq(contains(code, "    GREEN => 2"), true)
  assert_eq(contains(code, "pub fn Light::from_int(n : Int) -> Light {"), true)
  assert_eq(contains(code, "    _ => LIGHT_UNKNOWN"), true)
}

///|
test "nested message and enum declarations are hoisted to top level" {
  let src =
    #|message Outer {
    #|  string id = 1;
    #|  message Inner {
    #|    int32 value = 1;
    #|  }
    #|  enum Kind {
    #|    KIND_A = 0;
    #|    KIND_B = 1;
    #|  }
    #|  Inner inner = 2;
    #|  Kind kind = 3;
    #|}
  let proto = parse_proto(src)
  let mnames = proto.messages.map(fn(m) { m.name })
  assert_eq(mnames.contains("Outer"), true)
  assert_eq(mnames.contains("Inner"), true)
  assert_eq(proto.enums.length(), 1)
  assert_eq(proto.enums[0].name, "Kind")
  // Outer keeps only its own fields; the nested declarations are not fields.
  let outer = proto.messages.filter(fn(m) { m.name == "Outer" })[0]
  let fnames = outer.fields.map(fn(f) { f.name })
  assert_eq(fnames.length(), 3)
  assert_eq(fnames.contains("inner"), true)
  assert_eq(fnames.contains("kind"), true)
  // The hoisted Inner struct and Kind enum are generated.
  let code = generate_grpc(proto)
  assert_eq(contains(code, "pub(all) struct Inner {"), true)
  assert_eq(contains(code, "pub enum Kind {"), true)
}

///|
test "a oneof becomes a union enum, not flattened fields" {
  let src =
    #|message Event {
    #|  string id = 1;
    #|  oneof payload {
    #|    string text = 2;
    #|    int32 code = 3;
    #|  }
    #|}
  let proto = parse_proto(src)
  let ev = proto.messages[0]
  assert_eq(ev.name, "Event")
  // `id` stays a field; the oneof members do not leak into the field list.
  assert_eq(ev.fields.length(), 1)
  assert_eq(ev.fields[0].name, "id")
  assert_eq(ev.oneofs.length(), 1)
  assert_eq(ev.oneofs[0].name, "payload")
  assert_eq(ev.oneofs[0].variants.length(), 2)
  assert_eq(ev.oneofs[0].variants[0].name, "text")
  let code = generate_grpc(proto)
  assert_eq(contains(code, "pub enum EventPayload {"), true)
  assert_eq(contains(code, "  Text(String)"), true)
  assert_eq(contains(code, "  Code(Int)"), true)
  assert_eq(contains(code, "  payload : EventPayload"), true)
}

///|
test "a qualified type reference resolves to its simple (hoisted) name" {
  let src =
    #|message Outer {
    #|  message Inner { int32 v = 1; }
    #|}
    #|message User {
    #|  Outer.Inner ref = 1;
    #|  pkg.Thing thing = 2;
    #|  repeated Outer.Inner many = 3;
    #|}
  let proto = parse_proto(src)
  let user = proto.messages.filter(fn(m) { m.name == "User" })[0]
  // `Outer.Inner` -> `Inner` (the hoisted simple name); `pkg.Thing` -> `Thing`.
  assert_eq(user.fields[0].type_, "Inner")
  assert_eq(user.fields[1].type_, "Thing")
  assert_eq(user.fields[2].type_, "Array[Inner]")
}

///|
test "reserved numbers and names are captured and reuse is caught" {
  let src =
    #|message M {
    #|  reserved 2, 4 to 6;
    #|  reserved "old_name";
    #|  string ok = 1;
    #|  int32 bad = 2;
    #|  string old_name = 7;
    #|}
  let proto = parse_proto(src)
  let m = proto.messages[0]
  assert_eq(m.reserved_numbers, [2, 4, 5, 6])
  assert_eq(m.reserved_names, ["old_name"])
  let conflicts = proto_reserved_conflicts(m)
  // `bad` reuses reserved number 2; `old_name` reuses a reserved name.
  assert_eq(conflicts.length(), 2)
  assert_true(conflicts.contains("bad"))
  assert_true(conflicts.contains("old_name"))
}

///|
test "a message with no reserved conflicts reports none" {
  let src =
    #|message Clean {
    #|  reserved 3, 4;
    #|  string a = 1;
    #|  int32 b = 2;
    #|}
  let m = parse_proto(src).messages[0]
  assert_eq(proto_reserved_conflicts(m).length(), 0)
}

///|
test "generate streaming handler signatures" {
  let src =
    #|service Chat {
    #|  rpc Both (stream Msg) returns (stream Msg);
    #|}
    #|message Msg { string body = 1; }
  let code = generate_grpc(parse_proto(src))
  assert_eq(
    contains(code, "both : (Array[Msg]) -> Result[Array[Msg], @moonrpc.Status]"),
    true,
  )
}
