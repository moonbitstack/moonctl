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
/// Whether `moongql` has a GraphQL type for `ty`. A slice or an optional is that
/// of its element; `Bytes` and `Map` have none, and a field of one of those keeps
/// the generated `ToGql` impl from compiling, so it is dropped from the schema and
/// reported instead.
pub fn gql_expressible(ty : String) -> Bool {
  let base = if @text.ends_with(ty, "?") {
    ty[0:ty.length() - 1].to_owned()
  } else {
    ty
  }
  let element = if @text.starts_with(base, "Array[") &&
    @text.ends_with(base, "]") {
    base[6:base.length() - 1].to_owned()
  } else {
    base
  }
  // Everything else the `.api` vocabulary carries — a `type` block's own name
  // turned into a `#gql.type` — is expressible; `Bytes` and `Map` are not, and
  // there is no scalar to map them onto.
  match element {
    "Bytes" | "Map" => false
    _ => @text.starts_with(element, "Map[") == false
  }
}

///|
/// The annotated struct for one `type` block: its fields, minus the ones GraphQL
/// cannot carry. `skipped` collects what was left out so the command can say so.
fn gql_struct(t : @api.TypeDef, fields : Array[@api.Field]) -> String {
  let mut out = "///|\n/// `" +
    t.name +
    "`, from the `.api` `type` block.\n#gql.type\npub struct " +
    t.name +
    " {\n"
  for f in fields {
    if gql_expressible(f.type_) {
      out = out + "  " + f.mbt_name() + " : " + f.type_ + "\n"
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
  let reply = if r.resp != "" && gql_expressible(r.resp) {
    r.resp + "?"
  } else {
    "String"
  }
  let mut out = "///|\n/// `" +
    r.verb +
    " " +
    r.path +
    "` — the root field `" +
    name +
    "`.\n"
  out = out + (if r.verb == "get" { "#gql.query" } else { "#gql.mutation" })
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
    (if reply == "String" { @text.quote("TODO: " + r.handler) } else { "None" }) +
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
  let out = base_tree(
    mod_,
    st,
    dir,
    deps=["moonbitstack/moongql", "moonbitstack/mooncat"],
    imports=[gql, ("moonbitstack/mooncat", ""), (schema_pkg, "")],
    main=gql_main(mod_),
    context=false,
    rules=[("gql", generator_command("moonbitstack/moongql", "gql"))],
  )
  out.push({
    path: at(dir, gql_schema_pkg + "/moon.pkg"),
    content: pkg_file([gql]) +
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
