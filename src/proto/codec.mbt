// proto3 semantics: a scalar at its zero value is left out, a message field is
// present or absent, repeated numbers are written packed and read either way.

///|
priv struct Emit {
  out : StringBuilder
  mut depth : Int32
}

///|
fn Emit::new() -> Emit {
  { out: StringBuilder(), depth: 0, }
}

///|
fn Emit::line(self : Emit, text : String) -> Unit {
  for _ in 0..<self.depth {
    self.out.write_string("  ")
  }
  self.out.write_string(text)
  self.out.write_char('\n')
}

///|
fn Emit::open(self : Emit, text : String) -> Unit {
  self.line(text)
  self.depth += 1
}

///|
fn Emit::close(self : Emit, text : String) -> Unit {
  self.depth -= 1
  self.line(text)
}

///|
/// How one element of a field travels. Templates use `%n` for the field number,
/// `%v` for the value and `%r` for the reader; `raw` writes a bare element into a
/// packed run and is `None` for the length-delimited scalars.
priv enum Wire {
  Scalar(
    write~ : String,
    raw~ : String?,
    read~ : String,
    zero~ : String,
    nonzero~ : String
  )
  EnumOf(String)
  MessageOf(String)
}

///|
fn wire_of(proto : String, enums : Array[String]) -> Wire {
  fn num(write, raw, read, zero, nonzero) {
    Scalar(write~, raw=Some(raw), read~, zero~, nonzero~)
  }

  match proto {
    "double" =>
      num(
        "fixed64(%n, %v.reinterpret_as_uint64())", "write_fixed64(%v.reinterpret_as_uint64())",
        "%r.read_fixed64().reinterpret_as_double()", "0.0", "%v.reinterpret_as_uint64() != 0UL",
      )
    "float" =>
      num(
        "fixed32(%n, %v.reinterpret_as_uint())", "write_fixed32(%v.reinterpret_as_uint())",
        "Float::reinterpret_from_uint(%r.read_fixed32())", "0.0", "%v.reinterpret_as_uint() != 0U",
      )
    "int32" =>
      num(
        "int32(%n, %v)", "write_varint(%v.to_int64().reinterpret_as_uint64())", "%r.read_int32()",
        "0", "%v != 0",
      )
    "int64" =>
      num(
        "int64(%n, %v)", "write_varint(%v.reinterpret_as_uint64())", "%r.read_int64()",
        "0L", "%v != 0L",
      )
    "uint32" =>
      num(
        "uint32(%n, %v)", "write_varint(%v.to_uint64())", "%r.read_uint32()", "0U",
        "%v != 0U",
      )
    "uint64" =>
      num(
        "uint64(%n, %v)", "write_varint(%v)", "%r.read_uint64()", "0UL", "%v != 0UL",
      )
    "sint32" =>
      num(
        "sint32(%n, %v)", "write_varint(((%v << 1) ^ (%v >> 31)).reinterpret_as_uint().to_uint64())",
        "%r.read_sint32()", "0", "%v != 0",
      )
    "sint64" =>
      num(
        "sint64(%n, %v)", "write_varint(((%v << 1) ^ (%v >> 63)).reinterpret_as_uint64())",
        "%r.read_sint64()", "0L", "%v != 0L",
      )
    "fixed32" =>
      num(
        "fixed32(%n, %v)", "write_fixed32(%v)", "%r.read_fixed32()", "0U", "%v != 0U",
      )
    "fixed64" =>
      num(
        "fixed64(%n, %v)", "write_fixed64(%v)", "%r.read_fixed64()", "0UL", "%v != 0UL",
      )
    "sfixed32" =>
      num(
        "fixed32(%n, %v.reinterpret_as_uint())", "write_fixed32(%v.reinterpret_as_uint())",
        "%r.read_fixed32().reinterpret_as_int()", "0", "%v != 0",
      )
    "sfixed64" =>
      num(
        "fixed64(%n, %v.reinterpret_as_uint64())", "write_fixed64(%v.reinterpret_as_uint64())",
        "%r.read_fixed64().reinterpret_as_int64()", "0L", "%v != 0L",
      )
    "bool" =>
      num(
        "bool_(%n, %v)", "write_varint(if %v { 1UL } else { 0UL })", "%r.read_bool()",
        "false", "%v",
      )
    "string" =>
      Scalar(
        write="string_(%n, %v)",
        raw=None,
        read="%r.read_string()",
        zero="\"\"",
        nonzero="%v != \"\"",
      )
    "bytes" =>
      Scalar(
        write="bytes_(%n, %v)",
        raw=None,
        read="%r.read_bytes()",
        zero="b\"\"",
        nonzero="%v.length() > 0",
      )
    other => {
      let name = last_segment(other)
      if enums.contains(name) {
        EnumOf(name)
      } else {
        MessageOf(name)
      }
    }
  }
}

///|
fn fill(template : String, n : Int32, v : String, r : String) -> String {
  template
  .replace_all(old="%n", new=n.to_string())
  .replace_all(old="%v", new=v)
  .replace_all(old="%r", new=r)
}

///|
fn write_stmt(wire : Wire, n : Int32, v : String, w : String) -> String {
  match wire {
    Scalar(write~, ..) => w + "." + fill(write, n, v, "")
    EnumOf(_) => w + ".enum_(" + n.to_string() + ", " + v + ".to_int())"
    MessageOf(_) => w + ".message_(" + n.to_string() + ", " + v + ".encode())"
  }
}

///|
fn raw_stmt(wire : Wire, v : String, w : String) -> String? {
  match wire {
    Scalar(raw=Some(raw), ..) => Some(w + "." + fill(raw, 0, v, ""))
    EnumOf(_) =>
      Some(
        w +
        ".write_varint(" +
        v +
        ".to_int().to_int64().reinterpret_as_uint64())",
      )
    _ => None
  }
}

///|
fn read_expr(wire : Wire, r : String) -> String {
  match wire {
    Scalar(read~, ..) => fill(read, 0, "", r)
    EnumOf(name) => name + "::from_int(" + r + ".read_int32())"
    MessageOf(name) => name + "::decode(" + r + ".read_len_delim())"
  }
}

///|
fn zero_of(wire : Wire) -> String {
  match wire {
    Scalar(zero~, ..) => zero
    EnumOf(name) => name + "::from_int(0)"
    MessageOf(_) => "None"
  }
}

///|
fn nonzero(wire : Wire, v : String) -> String {
  match wire {
    Scalar(nonzero~, ..) => fill(nonzero, 0, v, "")
    EnumOf(_) => v + ".to_int() != 0"
    MessageOf(_) => v + " is Some(_)"
  }
}

///|
fn emit_encode(e : Emit, m : ProtoMessage, enums : Array[String]) -> Unit {
  e.line("///|")
  let this = if m.fields.length() + m.oneofs.length() == 0 {
    "_self"
  } else {
    "self"
  }
  e.open(
    "pub fn " + m.name + "::encode(" + this + " : " + m.name + ") -> Bytes {",
  )
  e.line("let w = @moonrpc.PbWriter::new()")
  for f in m.fields {
    let v = "self." + f.name
    let wire = wire_of(f.proto, enums)
    match f.label {
      Single =>
        match wire {
          MessageOf(_) => {
            e.open("if " + v + " is Some(x) {")
            e.line(write_stmt(wire, f.number, "x", "w"))
            e.close("}")
          }
          _ => {
            e.open("if " + nonzero(wire, v) + " {")
            e.line(write_stmt(wire, f.number, v, "w"))
            e.close("}")
          }
        }
      Repeated =>
        match raw_stmt(wire, "x", "packed") {
          Some(stmt) => {
            e.open("if " + v + ".length() > 0 {")
            e.line("let packed = @moonrpc.PbWriter::new()")
            e.open("for x in " + v + " {")
            e.line(stmt)
            e.close("}")
            e.line("w.bytes_(" + f.number.to_string() + ", packed.to_bytes())")
            e.close("}")
          }
          None => {
            e.open("for x in " + v + " {")
            e.line(write_stmt(wire, f.number, "x", "w"))
            e.close("}")
          }
        }
      MapOf(key~, value~) => {
        e.open("for k, x in " + v + " {")
        e.line("let entry = @moonrpc.PbWriter::new()")
        e.line(write_stmt(wire_of(key, enums), 1, "k", "entry"))
        e.line(write_stmt(wire_of(value, enums), 2, "x", "entry"))
        e.line("w.message_(" + f.number.to_string() + ", entry.to_bytes())")
        e.close("}")
      }
    }
  }
  for o in m.oneofs {
    let ename = m.name + cap_first(o.name)
    e.open("match self." + o.name + " {")
    for variant in o.variants {
      let stmt = write_stmt(
        wire_of(variant.proto, enums),
        variant.number,
        "x",
        "w",
      )
      e.line(
        "Some(" + ename + "::" + cap_first(variant.name) + "(x)) => " + stmt,
      )
    }
    e.line("None => ()")
    e.close("}")
  }
  e.line("w.to_bytes()")
  e.close("}")
  e.line("")
}

///|
fn emit_decode(e : Emit, m : ProtoMessage, enums : Array[String]) -> Unit {
  e.line("///|")
  e.open(
    "pub fn " +
    m.name +
    "::decode(bytes : Bytes) -> " +
    m.name +
    " raise @moonrpc.PbError {",
  )
  e.line("let r = @moonrpc.PbReader::new(bytes)")
  for f in m.fields {
    let (binding, init) = match f.label {
      Single => ("let mut ", zero_of(wire_of(f.proto, enums)))
      Repeated => ("let ", "[]")
      MapOf(..) => ("let ", "Map([])")
    }
    e.line(binding + f.name + " : " + field_type(f, enums) + " = " + init)
  }
  for o in m.oneofs {
    e.line(
      "let mut " + o.name + " : " + m.name + cap_first(o.name) + "? = None",
    )
  }
  e.open("while !r.eof() {")
  e.line("let (field, wt) = r.read_tag()")
  e.open("match field {")
  for f in m.fields {
    let n = f.number.to_string()
    let wire = wire_of(f.proto, enums)
    match f.label {
      Single =>
        match wire {
          MessageOf(_) =>
            e.line(
              n + " => " + f.name + " = Some(" + read_expr(wire, "r") + ")",
            )
          _ => e.line(n + " => " + f.name + " = " + read_expr(wire, "r"))
        }
      Repeated =>
        if raw_stmt(wire, "x", "w") is Some(_) {
          e.open(n + " =>")
          e.open("if wt is LengthDelim {")
          e.line("let packed = @moonrpc.PbReader::new(r.read_len_delim())")
          e.open("while !packed.eof() {")
          e.line(f.name + ".push(" + read_expr(wire, "packed") + ")")
          e.close("}")
          e.close("} else {")
          e.depth += 1
          e.line(f.name + ".push(" + read_expr(wire, "r") + ")")
          e.close("}")
          e.depth -= 1
        } else {
          e.line(n + " => " + f.name + ".push(" + read_expr(wire, "r") + ")")
        }
      MapOf(key~, value~) => {
        let kw = wire_of(key, enums)
        let vw = wire_of(value, enums)
        let vzero = match vw {
          MessageOf(name) => name + "::decode(b\"\")"
          _ => zero_of(vw)
        }
        e.open(n + " => {")
        e.line("let entry = @moonrpc.PbReader::new(r.read_len_delim())")
        e.line("let mut k = " + zero_of(kw))
        e.line("let mut x = " + vzero)
        e.open("while !entry.eof() {")
        e.open("match entry.read_tag() {")
        e.line("(1, _) => k = " + read_expr(kw, "entry"))
        e.line("(2, _) => x = " + read_expr(vw, "entry"))
        e.line("(_, other) => entry.skip(other)")
        e.close("}")
        e.close("}")
        e.line(f.name + "[k] = x")
        e.close("}")
      }
    }
  }
  for o in m.oneofs {
    let ename = m.name + cap_first(o.name)
    for variant in o.variants {
      let value = read_expr(wire_of(variant.proto, enums), "r")
      e.line(
        variant.number.to_string() +
        " => " +
        o.name +
        " = Some(" +
        ename +
        "::" +
        cap_first(variant.name) +
        "(" +
        value +
        "))",
      )
    }
  }
  e.line("_ => r.skip(wt)")
  e.close("}")
  e.close("}")
  let names = m.fields.map(f => f.name)
  for o in m.oneofs {
    names.push(o.name)
  }
  e.line(m.name + "::{ " + names.join(", ") + " }")
  e.close("}")
  e.line("")
}

///|
/// One `@moonrpc.Handler` for `r`, decoding requests and encoding replies around
/// the typed handler; a request that fails to decode ends the call with
/// `InvalidArgument`.
fn emit_handler(e : Emit, path : String, r : Rpc) -> Unit {
  let call = "(self." + @text.to_snake(r.name) + ")"
  let fail = "ctx.fail(status.code(), status.name())"
  let bad = "ctx.fail(@moonrpc.Status::InvalidArgument.code(), err.to_string())"
  let decode = r.request + "::decode(raw)"
  let reply = if r.server_streaming {
    "replies.map(reply => reply.encode())"
  } else {
    "reply.encode()"
  }
  let ok = if r.server_streaming { "Ok(replies)" } else { "Ok(reply)" }
  let none = if r.server_streaming { "[]" } else { "b\"\"" }
  let key = "handlers[" + @text.quote(path) + "] = "
  match (r.client_streaming, r.server_streaming) {
    (false, _) => {
      let kind = if r.server_streaming { "ServerStreaming" } else { "Unary" }
      e.open(key + kind + "((ctx, raw) => {")
      e.line(
        "let req = " +
        decode +
        " catch { err => { " +
        bad +
        "; return " +
        none +
        " } }",
      )
      e.open("match " + call + "(req) {")
      e.line(ok + " => " + reply)
      e.line("Err(status) => { " + fail + "; " + none + " }")
      e.close("}")
      e.close("})")
    }
    (true, false) => {
      e.open(key + "ClientStreaming((ctx, raws) => {")
      e.line("let reqs : Array[" + r.request + "] = []")
      e.open("for raw in raws {")
      e.line(
        "reqs.push(" +
        decode +
        " catch { err => { " +
        bad +
        "; return b\"\" } })",
      )
      e.close("}")
      e.open("match " + call + "(reqs) {")
      e.line("Ok(reply) => reply.encode()")
      e.line("Err(status) => { " + fail + "; b\"\" }")
      e.close("}")
      e.close("})")
    }
    (true, true) => {
      e.open(key + "Bidi(ctx => {")
      e.line("let reqs : Array[" + r.request + "] = []")
      e.line("let mut broken = false")
      e.open("{")
      e.open("on_message: raw => {")
      e.line("if broken { return [] }")
      e.line(
        "reqs.push(" +
        decode +
        " catch { err => { broken = true; " +
        bad +
        "; return [] } })",
      )
      e.line("[]")
      e.close("},")
      e.open("on_end: () => {")
      e.line("if broken { return [] }")
      e.open("match " + call + "(reqs) {")
      e.line("Ok(replies) => replies.map(reply => reply.encode())")
      e.line("Err(status) => { " + fail + "; [] }")
      e.close("}")
      e.close("},")
      e.close("}")
      e.close("})")
    }
  }
}

///|
fn emit_handlers(e : Emit, full : String, s : ProtoService) -> Unit {
  e.line("///|")
  e.line(
    "/// Every RPC of `" +
    full +
    "` keyed by its `:path`, ready for `GrpcServer`.",
  )
  e.open(
    "pub fn " +
    s.name +
    "Server::handlers(self : " +
    s.name +
    "Server) -> Map[String, @moonrpc.Handler] {",
  )
  e.line("let handlers : Map[String, @moonrpc.Handler] = Map([])")
  for r in s.rpcs {
    emit_handler(e, "/" + full + "/" + r.name, r)
  }
  e.line("handlers")
  e.close("}")
  e.line("")
}

///|
/// The MoonBit type a field is declared with: a singular message is optional.
fn field_type(f : ProtoField, enums : Array[String]) -> String {
  match (f.label, wire_of(f.proto, enums)) {
    (Single, MessageOf(name)) => name + "?"
    _ => f.type_
  }
}

///|
/// Encoders and decoders for every message in `proto`, and a handler table per
/// service.
fn codecs(proto : Proto) -> String {
  let enums = proto.enums.map(x => x.name)
  let e = Emit::new()
  for m in proto.messages {
    emit_encode(e, m, enums)
    emit_decode(e, m, enums)
  }
  for s in proto.services {
    let full = if proto.package_ == "" {
      s.name
    } else {
      proto.package_ + "." + s.name
    }
    emit_handlers(e, full, s)
  }
  e.out.to_string()
}
