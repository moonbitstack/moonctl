// Request binding for generated handlers.
//
// goctl's `httpx.Parse` takes a request struct and fills it from the path, the
// query string, the headers and the JSON body according to the field's tags. The
// generated service does the same, but as code written out per request type: a
// `bind_<type>` function that reads each field from the place its tag names and
// returns the first thing it could not read, so the handler answers 400 with the
// field named rather than handing the logic a half-filled struct.
//
// The binder belongs to the generated `internal/types` package, next to the struct
// it builds: the handlers call it, and it is regenerated with them.

///|
/// The `bind_*` helper that reads a text field of type `t` from its wire form, or
/// `None` when a text field of that type has no reading (`Array`, `Map`, a nested
/// message — the body is the only place those may come from).
fn text_binder(t : String) -> String? {
  match t {
    "String" => Some("bind_text")
    "Int32" => Some("bind_int32")
    "Int64" => Some("bind_int64")
    "UInt32" => Some("bind_uint32")
    "UInt64" => Some("bind_uint64")
    "Double" => Some("bind_double")
    "Float" => Some("bind_float")
    "Bool" => Some("bind_bool")
    _ => None
  }
}

///|
/// `ty` without the `?` that makes it optional: the type a text field is parsed as.
fn base_type(ty : String) -> String {
  if @text.ends_with(ty, "?") {
    ty[0:ty.length() - 1].to_owned()
  } else {
    ty
  }
}

///|
/// Whether a field may be absent: the tag said `optional`/`omitempty`, or its type
/// is spelled optional (`String?`).
fn may_absent(f : @api.Field) -> Bool {
  f.optional() || @text.ends_with(f.type_, "?")
}

///|
/// Where a field's value comes from, as the generated code reads it.
fn bind_place(b : @api.Bind) -> String {
  match b {
    @api.Path => "path"
    @api.Query => "form"
    @api.Header => "header"
    @api.Body => "body"
  }
}

///|
/// The request types `spec`'s routes declare, in the order they first appear, each
/// with its fields — the types a binder is written for. A route naming a type the
/// spec never declares is left out: there is nothing to build.
pub fn bound_types(spec : @api.Spec) -> Array[(String, Array[@api.Field])] {
  let out : Array[(String, Array[@api.Field])] = []
  for r in spec.routes {
    if r.req == "" {
      continue
    }
    let mut seen = false
    for entry in out {
      if entry.0 == r.req {
        seen = true
      }
    }
    if seen {
      continue
    }
    for t in spec.types {
      if t.name == r.req {
        out.push((t.name, @api.flat_fields(t, spec.types)))
      }
    }
  }
  out
}

///|
/// The helpers `fields` need, in a stable order, each once.
fn needed_helpers(fields : Array[@api.Field]) -> Array[String] {
  let out : Array[String] = []
  for f in fields {
    // A text field is taken as it arrived, so it needs no helper of its own.
    if f.bind() == @api.Body || f.type_ == "String" || f.type_ == "String?" {
      continue
    }
    match text_binder(base_type(f.type_)) {
      Some(h) => if out.contains(h) == false { out.push(h) }
      None => ()
    }
  }
  out
}

///|
/// The body of one request-field helper, by name.
fn helper_src(name : String) -> String {
  let (ty, call) = match name {
    "bind_text" => ("String", "")
    "bind_int32" => ("Int32", "@string.parse_int(s)")
    "bind_int64" => ("Int64", "@string.parse_int64(s)")
    "bind_uint32" => ("UInt32", "@string.parse_uint(s)")
    "bind_uint64" => ("UInt64", "@string.parse_uint64(s)")
    "bind_double" => ("Double", "@string.parse_double(s)")
    "bind_float" => ("Float", "Float::from_double(@string.parse_double(s))")
    _ => ("Bool", "parse_bool(s)")
  }
  if name == "bind_text" {
    return "///|\n/// A text field, taken as it arrived.\nfn bind_text(s : String) -> String? {\n  Some(s)\n}\n\n"
  }
  if name == "bind_bool" {
    return "///|\n/// A boolean field: what every request format spells it as.\nfn bind_bool(s : String) -> Bool? {\n  match s {\n    \"true\" | \"TRUE\" | \"1\" => Some(true)\n    \"false\" | \"FALSE\" | \"0\" => Some(false)\n    _ => None\n  }\n}\n\n"
  }
  "///|\n/// A `" +
  ty +
  "` field, read from its text.\nfn " +
  name +
  "(s : String) -> " +
  ty +
  "? {\n  try {\n    Some(" +
  call +
  ")\n  } catch {\n    _ => None\n  }\n}\n\n"
}

///|
/// The statement that binds `f` from its place, for a field that is not in the body:
/// read the text, then read the type out of it. A field that may be absent keeps
/// `None` when the request left it out; one that may not is refused by name.
fn text_bind_stmt(f : @api.Field) -> String {
  let place = bind_place(f.bind())
  let key = f.json_name()
  let slot = f.mbt_name()
  let ty = f.type_
  let absent = may_absent(f)
  let source = reader(place, key)
  let want = place + " \\\"" + key + "\\\""
  if ty == "String" || ty == "String?" {
    if absent {
      return "  let " +
        slot +
        " : String? = match " +
        source +
        " {\n    Some(text) => Some(text)\n    None => None\n  }\n"
    }
    return "  let " +
      slot +
      " : String = match " +
      source +
      " {\n    Some(text) => text\n    None => return Err(\"" +
      want +
      " is missing\")\n  }\n"
  }
  match text_binder(base_type(ty)) {
    None =>
      if absent {
        "  let " + slot + " : " + ty + " = None\n"
      } else {
        "  return Err(\"" +
        want +
        ": " +
        ty +
        " has no text form; bind it from the body\")\n"
      }
    Some(binder) =>
      if absent {
        "  let " +
        slot +
        " : " +
        ty +
        " = match " +
        source +
        " {\n    Some(text) =>\n      match " +
        binder +
        "(text) {\n        Some(value) => Some(value)\n        None => return Err(\"" +
        want +
        ": want " +
        base_type(ty) +
        "\")\n      }\n    None => None\n  }\n"
      } else {
        "  let " +
        slot +
        " : " +
        ty +
        " = match " +
        source +
        " {\n    Some(text) =>\n      match " +
        binder +
        "(text) {\n        Some(value) => value\n        None => return Err(\"" +
        want +
        ": want " +
        base_type(ty) +
        "\")\n      }\n    None => return Err(\"" +
        want +
        " is missing\")\n  }\n"
      }
  }
}

///|
/// The expression that reads a field's text out of `place`.
fn reader(place : String, key : String) -> String {
  let q = @text.quote(key)
  match place {
    "path" => "ctx.param(" + q + ")"
    "form" => "ctx.query(" + q + ")"
    "header" => "ctx.request.header(" + q + ")"
    _ => "None"
  }
}

///|
/// The statement that binds `f` out of the JSON body: the member the tag names,
/// read as the field's type. A field that may be absent stays `None` when the body
/// carries no such member.
fn body_bind_stmt(f : @api.Field) -> String {
  let key = f.json_name()
  let slot = f.mbt_name()
  let ty = f.type_
  let optional = may_absent(f)
  let missing = if optional {
    "None"
  } else {
    "return Err(\"body \\\"" + key + "\\\" is missing\")"
  }
  let bad = "return Err(\"body \\\"" + key + "\\\": want " + ty + "\")"
  let read = if optional {
    "try {\n            Some(@json.from_json(value))\n          } catch {\n            _ => " +
    bad +
    "\n          }"
  } else {
    "try {\n            @json.from_json(value)\n          } catch {\n            _ => " +
    bad +
    "\n          }"
  }
  "  let " +
  slot +
  " : " +
  ty +
  " = match body {\n    Some(Object(members)) =>\n      match members.get(" +
  @text.quote(key) +
  ") {\n        Some(value) =>\n          " +
  read +
  "\n        None => " +
  missing +
  "\n      }\n    _ => " +
  missing +
  "\n  }\n"
}

///|
/// `bind_<type>` for one request type: read every field from the place its tag
/// names, then build the struct. A field bound from the body and one bound from the
/// path are read the same way the request puts them there, so a request whose body
/// and path disagree takes each value from where its tag says.
pub fn render_binder(name : String, fields : Array[@api.Field]) -> String {
  let fn_name = "bind_" + @text.to_snake(name)
  let mut cols = ""
  for f in fields {
    cols = if cols == "" { f.mbt_name() } else { cols + ", " + f.mbt_name() }
  }
  let from_body = fields.any(f => f.bind() == @api.Body)
  let mut out = "///|\n/// Bind `" +
    name +
    "` from the request: `path`, `form` and `header` values from the places their\n/// tags name, everything else from the JSON body. `Err` names the first field that\n/// was missing or would not read.\npub fn " +
    fn_name +
    "(ctx : @moonapi.Context) -> Result[" +
    name +
    ", String] {\n"
  if from_body {
    out = out + "  let body = ctx.body_json()\n"
  }
  for f in fields {
    out = out +
      (if f.bind() == @api.Body {
        body_bind_stmt(f)
      } else {
        text_bind_stmt(f)
      })
  }
  out + "  Ok({ " + cols + ", })\n}\n\n"
}

///|
/// Every binder `spec` needs, with the helpers they read through, as the
/// `internal/types` package's generated source tail. Empty when no route declares a
/// request type.
pub fn render_binders(spec : @api.Spec) -> String {
  let types = bound_types(spec)
  if types.length() == 0 {
    return ""
  }
  let helpers : Array[String] = []
  for entry in types {
    for h in needed_helpers(entry.1) {
      if helpers.contains(h) == false {
        helpers.push(h)
      }
    }
  }
  let order = [
    "bind_text", "bind_int32", "bind_int64", "bind_uint32", "bind_uint64", "bind_double",
    "bind_float", "bind_bool",
  ]
  let mut out = ""
  for h in order {
    if helpers.contains(h) {
      out = out + helper_src(h)
    }
  }
  for entry in types {
    out = out + render_binder(entry.0, entry.1)
  }
  out
}
