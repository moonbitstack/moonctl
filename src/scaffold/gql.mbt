// The GraphQL service tree, declared with `#gql` annotations.
//
// `moongql`'s generator reads the annotated structs and root fields and writes
// `register(schema, resolvers)` into `schema.g.mbt` on build, so what this
// generator emits is the schema itself rather than a program that builds one. The
// resolvers are the annotated functions: their parameters are the field's
// arguments, and their bodies are where the author works.

///|
/// The package the annotated schema lives in.
let gql_schema_pkg = "internal/schema"

///|
/// How a field of the spec's MoonBit type reaches GraphQL.
priv enum GqlField {
  /// The MoonBit type is a GraphQL type already.
  Direct
  /// `Bytes`: the `Base64` scalar. The field is declared as the text that scalar
  /// carries, since `ToGql` has no impl for `Bytes` and none can be written — the
  /// trait and the type both belong to another package.
  Base64
  /// `Map[String, V]`: the `JSON` scalar, with the field declared as a `Json`
  /// object for the same reason.
  JsonMap
  /// A map keyed by something other than a `String`: an object's member names are
  /// strings, so there is no shape to give it.
  Dropped
}

///|
/// `ty` without the `?` that makes it optional.
fn gql_base(ty : String) -> (String, Bool) {
  if @text.ends_with(ty, "?") && ty.length() > 1 {
    (ty[0:ty.length() - 1].to_owned(), true)
  } else {
    (ty, false)
  }
}

///|
/// The MoonBit type of a `Map[…]`'s value, or `None` when the key is not a
/// `String` — a GraphQL object's field names are strings, so a map keyed by
/// anything else has no object to become.
fn gql_map_value(ty : String) -> String? {
  let close = @text.index_of_str(ty, "]")
  if close <= 4 {
    return None
  }
  // `Map[K, V]` — the key is what stands before the first comma of the inside, so
  // a value that is itself generic (`Map[String, Array[Int32]]`) still reads right.
  let inside = @text.trim(ty[4:close].to_owned())
  let comma = @text.index_of_str(inside, ",")
  if comma < 0 {
    return None
  }
  let key = @text.trim(inside[0:comma].to_owned())
  if key != "String" {
    return None
  }
  Some(@text.trim(inside[comma + 1:].to_owned()))
}

///|
/// The GraphQL shape of a field's MoonBit type. An optional and a slice take
/// their element's shape; `Bytes` becomes the `Base64` scalar and a `Map[String,
/// V]` the `JSON` one; every other name is a type the schema declares.
fn gql_field_kind(ty : String) -> GqlField {
  let element = gql_element(ty)
  if element == "Bytes" {
    return Base64
  }
  if @text.starts_with(element, "Map[") {
    return match gql_map_value(element) {
      Some(_) => JsonMap
      None => Dropped
    }
  }
  Direct
}

///|
/// Whether the schema can carry `ty` — directly, or through the scalar this
/// generator declares for it.
pub fn gql_expressible(ty : String) -> Bool {
  (gql_field_kind(ty) is Dropped) == false
}

///|
/// The annotated struct for one `type` block. A field GraphQL carries directly is
/// the struct field the spec declared; `Bytes` and `Map[String, V]` are declared
/// as the text and the object their scalars carry, with the scalar named on the
/// field, because neither has a `ToGql` impl this generator may write.

///|
/// The annotated struct for one `type` block. A field GraphQL carries directly is
/// a struct field; `Bytes` and `Map[String, V]` are skipped in the struct and
/// reached through a `#gql.field` method returning the text or the object of their
/// scalar, since neither type has a `ToGql` impl this generator may write.
fn gql_struct(t : @api.TypeDef, fields : Array[@api.Field]) -> String {
  let mut out = "///|\n/// `" +
    t.name +
    "`, from the `.api` `type` block.\n#gql.type\npub struct " +
    t.name +
    " {\n"
  for f in fields {
    match gql_field_kind(f.type_) {
      Direct => out = out + "  " + f.mbt_name() + " : " + f.type_ + "\n"
      Base64 =>
        out = out +
          "  /// The base64 text of `" +
          f.mbt_name() +
          "`, which is what the `Base64` scalar carries.\n  #gql.field(kind=\"Base64\")\n  " +
          f.mbt_name() +
          " : String\n"
      JsonMap =>
        out = out +
          "  /// `" +
          f.mbt_name() +
          "` as the object the `JSON` scalar carries, one member per key.\n  #gql.field(kind=\"JSON\")\n  " +
          f.mbt_name() +
          " : Json\n"
      Dropped => ()
    }
  }
  out + "}\n"
}

///|
/// The fields of a `type` block that GraphQL has no type for, as
/// `<type>.<field> (<type>)`, for the command to report.
pub fn gql_dropped_fields(spec : @api.Spec) -> Array[String] {
  let out : Array[String] = []
  for t in spec.types {
    for f in @api.flat_fields(t, spec.types) {
      if gql_expressible(f.type_) == false {
        out.push(t.name + "." + f.mbt_name() + " (" + f.type_ + ")")
      }
    }
  }
  out
}

///|
/// The element type of a field's MoonBit type: a slice's element, or the type
/// itself. `Bytes` and `Map[…]` are what the two scalars are about.
fn gql_element(ty : String) -> String {
  let (base, _) = gql_base(ty)
  if @text.starts_with(base, "Array[") && @text.ends_with(base, "]") {
    base[6:base.length() - 1].to_owned()
  } else {
    base
  }
}

///|
/// Whether any field of the spec is `Bytes`, which is what makes the generated
/// package import the base64 encoder its scalar's text comes from.
fn gql_uses_base64(spec : @api.Spec) -> Bool {
  for t in spec.types {
    for f in @api.flat_fields(t, spec.types) {
      if gql_element(f.type_) == "Bytes" {
        return true
      }
    }
  }
  false
}

///|
/// The `:name` segments of a route path, in order.
fn gql_path_params(path : String) -> Array[String] {
  let out : Array[String] = []
  for part in path.split("/") {
    let one : String = part.to_owned()
    if @text.starts_with(one, ":") {
      out.push(one[1:].to_owned())
    }
  }
  out
}

///|
/// A route as a root field: its arguments are the request type's fields (a `path`
/// field's type is the URL segment's), its type is the declared reply, and its
/// body is a stub for the author to fill in.
fn gql_root_field(spec : @api.Spec, r : @api.Route, name : String) -> String {
  let args : Array[(String, String)] = []
  let req = @api.find_type(spec.types, r.req)
  if req is Some(t) {
    for f in @api.flat_fields(t, spec.types) {
      if gql_expressible(f.type_) {
        args.push((f.mbt_name(), f.type_))
      }
    }
  } else {
    // No request type: the URL segments are the arguments.
    for p in gql_path_params(r.path) {
      args.push((p, "String"))
    }
  }
  let declared = r.resp != "" && gql_expressible(r.resp)
  // A subscription answers with the events a subscriber receives, one array of
  // them, so its type is a list of the declared event type rather than the type.
  let reply = if r.stream {
    "Array[" + (if declared { r.resp } else { "String" }) + "]"
  } else if declared {
    r.resp + "?"
  } else {
    "String"
  }
  let mut out = "///|\n/// `" +
    r.verb +
    " " +
    r.path +
    "` — the " +
    (if r.stream { "subscription" } else { "root field" }) +
    " `" +
    name +
    "`" +
    (if r.stream {
      ", one event per `" + (if declared { r.resp } else { "String" }) + "`"
    } else {
      ""
    }) +
    ".\n"
  out = out +
    (if r.stream {
      "#gql.subscription"
    } else if r.verb == "get" {
      "#gql.query"
    } else {
      "#gql.mutation"
    })
  out = out + "\npub fn " + name + "("
  if args.length() > 0 {
    out = out + "\n"
    for a in args {
      out = out + "  " + a.0 + " : " + a.1 + ",\n"
    }
  }
  out = out + ") -> " + reply + " {\n"
  // The parameters keep their names — they are the field's arguments — and the
  // stub acknowledges them, so a fresh project has no unused-parameter warning.
  let slots : Array[String] = []
  for a in args {
    slots.push(a.0)
  }
  if slots.length() == 1 {
    out = out + "  ignore(" + slots[0] + ")\n"
  } else if slots.length() > 1 {
    out = out + "  ignore((" + slots.join(", ") + "))\n"
  }
  out = out +
    "  " +
    (if r.stream {
      "[]"
    } else if reply == "String" {
      @text.quote("TODO: " + r.handler)
    } else {
      "None"
    }) +
    "\n}\n"
  out
}

///|
/// The seeded schema for `spec`: one annotated struct per `type` block, one root
/// field per route.
pub fn gql_schema_for(spec : @api.Spec) -> String {
  let mut out = "// Seeded by moonctl from the `.api` spec; edit it as you like.\n//\n// Each `#gql.type` struct is a GraphQL type and each `#gql.query`/\n// `#gql.mutation` a root field, with its parameters as the field's arguments.\n// `register(schema, resolvers)` is generated from these on build.\n"
  for t in spec.types {
    out = out + "\n" + gql_struct(t, @api.flat_fields(t, spec.types))
  }
  let taken : Array[String] = []
  for r in spec.routes {
    let base = r.handler
    let mut name = base
    let mut n = 2
    while taken.contains(name) {
      name = base + "_" + n.to_string()
      n = n + 1
    }
    taken.push(name)
    out = out + "\n" + gql_root_field(spec, r, name)
  }
  out
}

///|
/// The two conversions a `Base64` field needs and the schema cannot state: the
/// text a `Bytes` value is published as, and the bytes a client's text means. They
/// are generated rather than left to the author, since the encoding is what makes
/// the field's GraphQL type true.
fn gql_scalars_src() -> String {
  let src =
    #|// Code generated by moonctl. DO NOT EDIT.
    #|
    #|///|
    #|/// The base64 text the `Base64` scalar carries, from the bytes of a field.
    #|pub fn base64_of(bytes : Bytes) -> String {
    #|  @base64.encode(bytes[:])
    #|}
    #|
    #|///|
    #|/// The bytes a base64 text holds: `None` when the text is not base64, so a
    #|/// malformed input is refused rather than read as an empty value.
    #|pub fn bytes_of_base64(text : String) -> Bytes? {
    #|  let decoded = @base64.decode(text) catch {
    #|    _ => return None
    #|  }
    #|  Some(decoded)
    #|}
  src + "\n"
}

///|
/// The entry point of a GraphQL service: build the schema from the annotations,
/// serve it, and print where.
fn gql_main(module_ : String) -> String {
  let src =
    #|///|
    #|/// The %svc service: build the schema from its `#gql` annotations and serve it
    #|/// on mooncat.
    #|async fn main {
    #|  let cfg = @config.Config::new()
    #|  let (schema, resolvers) = @schema.build()
    #|  let app = @moongql.graphql_app(schema, resolvers)
    #|  println("%svc serving GraphQL on " + cfg.host + ":" + cfg.port.to_string())
    #|  @mooncat.serve(app, host=cfg.host, port=cfg.port)
    #|}
  src.replace_all(old="%svc", new=module_) + "\n"
}

// The generated schema package needs a `build()` the entry point calls: moonmcp's
// `register` composes the schema, and this hands it out with the resolvers.

///|
/// `build()` for the schema package: a fresh schema, the resolvers registered into
/// it, and the pair the application serves.
fn gql_build_src() -> String {
  "///|\n/// The schema and resolvers of this service, built from the annotations beside\n/// this function.\npub fn build() -> (@moongql.Schema, @moongql.Resolvers) {\n  let schema = @moongql.Schema::new()\n  let resolvers = @moongql.Resolvers::new()\n  register(schema, resolvers)\n  (schema, resolvers)\n}\n"
}

///|
/// The layered GraphQL tree for `spec` under `dir`: `internal/schema` with the
/// annotated types and root fields (seeded once — the resolvers are yours to
/// write), the rule that regenerates the schema from them, `internal/config` and
/// the entry point serving it on 12000.
///
/// Hand the result to `tree_plan` to keep what the author has filled in.
pub fn generate_gql_tree(
  spec : @api.Spec,
  style? : @style.Style,
  dir~ : String = "",
) -> Array[TreeFile] {
  let st = style.unwrap_or(@style.Style::gozero())
  let mod_ = spec.service
  let gql = ("moonbitstack/moongql", "")
  let schema_pkg = mod_ + "/" + gql_schema_pkg
  // `Bytes` is base64-encoded for its scalar, and a map is rendered to JSON: the
  // schema package imports each library only when a field of the spec needs it.
  let needs_base64 = gql_uses_base64(spec)
  let deps = ["moonbitstack/moongql", "moonbitstack/mooncat"]
  if needs_base64 {
    deps.push("moonbitstack/moonbase")
  }
  let schema_imports : Array[(String, String)] = [gql]
  if needs_base64 {
    schema_imports.push(("moonbitstack/moonbase/base64", "base64"))
  }
  let out = base_tree(
    mod_,
    st,
    dir,
    deps~,
    imports=[gql, ("moonbitstack/mooncat", ""), (schema_pkg, "")],
    main=gql_main(mod_),
    context=false,
    rules=[("gql", generator_command("moonbitstack/moongql", "gql"))],
  )
  out.push({
    path: at(dir, gql_schema_pkg + "/moon.pkg"),
    content: pkg_file(schema_imports) +
    "\ndev_build(rule: \"gql\", input: \"" +
    st.format("schema") +
    ".mbt\", output: \"" +
    st.format("schema") +
    ".g.mbt\")\n\nformatter(ignore: [ \"" +
    st.format("schema") +
    ".g.mbt\" ])\n",
    regen: Once,
  })
  out.push({
    path: at(dir, gql_schema_pkg + "/" + st.format("schema") + ".mbt"),
    content: gql_schema_for(spec) + "\n" + gql_build_src(),
    regen: Once,
  })
  if needs_base64 {
    out.push({
      path: at(dir, gql_schema_pkg + "/" + st.format("scalars") + ".mbt"),
      content: gql_scalars_src(),
      regen: Always,
    })
  }
  // A root field to ask for, whatever the resolvers end up answering: asking the
  // schema what it is keeps the seeded test true after the stubs are filled in.
  if spec.routes.any(r => r.verb == "get") {
    out.push({
      path: at(dir, gql_schema_pkg + "/" + st.format("schema") + "_test.mbt"),
      content: "///|\ntest \"the schema answers\" {\n  let (schema, resolvers) = @schema.build()\n  let got = @moongql.execute(schema, resolvers, \"{ __typename }\")\n  assert_eq(got, { \"data\": { \"__typename\": \"Query\" } })\n}\n",
      regen: Once,
    })
  }
  out
}
