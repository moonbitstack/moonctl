///|
fn kit() -> Proto {
  let src =
    #|syntax = "proto3";
    #|package kit;
    #|enum Mood { CALM = 0; BUSY = 1; }
    #|message Point { sint32 x = 1; }
    #|message Bag {
    #|  double d = 1;
    #|  string s = 2;
    #|  Mood mood = 3;
    #|  Point at = 4;
    #|  repeated int32 nums = 5;
    #|  repeated string tags = 6;
    #|  map<string, Point> named = 7;
    #|  oneof pick { string name = 8; Point spot = 9; }
    #|}
    #|service Kit {
    #|  rpc Get (Point) returns (Bag);
    #|  rpc Walk (Point) returns (stream Point);
    #|  rpc Sum (stream Point) returns (Point);
    #|  rpc Chat (stream Point) returns (stream Point);
    #|}
  parse_proto(src)
}

///|
test "fields carry their proto type and label" {
  let bag = kit().messages[1]
  assert_eq(bag.fields[2].proto, "Mood")
  assert_eq(bag.fields[4].label, Repeated)
  assert_eq(bag.fields[6].label, MapOf(key="string", value="Point"))
  assert_eq(bag.oneofs[0].variants[1].label, Single)
}

///|
test "a singular message field is optional and a oneof may be unset" {
  let code = generate_grpc(kit())
  assert_eq(contains(code, "  at : Point?\n"), true)
  assert_eq(contains(code, "  pick : BagPick?\n"), true)
  assert_eq(contains(code, "  mood : Mood\n"), true)
}

///|
test "proto3 zero values are skipped, floats by their bits" {
  let code = generate_grpc(kit())
  assert_eq(contains(code, "if self.d.reinterpret_as_uint64() != 0UL {"), true)
  assert_eq(contains(code, "if self.s != \"\" {"), true)
  assert_eq(contains(code, "if self.mood.to_int() != 0 {"), true)
  assert_eq(contains(code, "if self.at is Some(x) {"), true)
}

///|
test "repeated numbers are packed, repeated strings are not" {
  let code = generate_grpc(kit())
  assert_eq(contains(code, "w.bytes_(5, packed.to_bytes())"), true)
  assert_eq(contains(code, "if wt is LengthDelim {"), true)
  assert_eq(contains(code, "w.string_(6, x)"), true)
  assert_eq(contains(code, "6 => tags.push(r.read_string())"), true)
}

///|
test "map entries and oneof members travel as their own fields" {
  let code = generate_grpc(kit())
  assert_eq(contains(code, "entry.message_(2, x.encode())"), true)
  assert_eq(contains(code, "let mut x = Point::decode(b\"\")"), true)
  assert_eq(
    contains(code, "Some(BagPick::Spot(x)) => w.message_(9, x.encode())"),
    true,
  )
  assert_eq(
    contains(
      code, "9 => pick = Some(BagPick::Spot(Point::decode(r.read_len_delim())))",
    ),
    true,
  )
  assert_eq(
    contains(code, "Bag::{ d, s, mood, at, nums, tags, named, pick }"),
    true,
  )
}

///|
test "every call kind gets an entry in the handler table" {
  let code = generate_grpc(kit())
  assert_eq(contains(code, "handlers[\"/kit.Kit/Get\"] = Unary("), true)
  assert_eq(
    contains(code, "handlers[\"/kit.Kit/Walk\"] = ServerStreaming("),
    true,
  )
  assert_eq(
    contains(code, "handlers[\"/kit.Kit/Sum\"] = ClientStreaming("),
    true,
  )
  assert_eq(contains(code, "handlers[\"/kit.Kit/Chat\"] = Bidi("), true)
  assert_eq(contains(code, "@moonrpc.Status::InvalidArgument.code()"), true)
}

///|
test "qualified rpc types resolve to their simple names" {
  let src =
    #|service S { rpc Go (pkg.In) returns (stream pkg.Out); }
  let proto = parse_proto(src)
  assert_eq(proto.services[0].rpcs[0].request, "In")
  assert_eq(proto.services[0].rpcs[0].response, "Out")
}
