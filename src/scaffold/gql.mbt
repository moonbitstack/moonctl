// The GraphQL service tree: the schema generated from a `.api` spec under
// `internal/schema`, the author's resolvers under `internal/logic`, served as an
// ASGI application on mooncat.

///|
/// The resolvers seeded for `spec`: `ping` answers, and each type's lookup starts
/// out empty for the author to fill.
fn resolvers_src(spec : @api.Spec) -> String {
  let out = StringBuilder()
  out.write_string(
    "///|\n/// The root fields' resolvers. An object field reads its parent's member of the\n/// same name unless a resolver for it is added here.\npub fn resolvers(_svc : @svc.ServiceContext) -> @moongql.Resolvers {\n  let resolvers = @moongql.Resolvers::new()\n  resolvers.field(\"Query\", \"ping\", _ => Json::string(\"pong\"))\n",
  )
  for t in spec.types {
    out.write_string(
      "  resolvers.field(\"Query\", " +
      @text.quote(@text.lower_first(t.name)) +
      ", _ => Json::null())\n",
    )
  }
  out.write_string("  resolvers\n}\n")
  out.to_string()
}

///|
/// The layered GraphQL tree for `spec` under `dir`: `internal/schema` with
/// `build_schema()` (rewritten on every run), `internal/logic` with the resolvers
/// and a test that queries `ping`, `internal/config`/`internal/svc` (seeded once),
/// and the entry point serving `graphql_app` on 12000.
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
  let schema_pkg = mod_ + "/internal/schema"
  let logic_pkg = mod_ + "/internal/logic"
  let svc_pkg = mod_ + "/internal/svc"
  let config_pkg = mod_ + "/internal/config"
  let out = base_tree(
    mod_,
    st,
    dir,
    deps=["moonbitstack/moongql", "moonbitstack/mooncat"],
    imports=[
      gql,
      ("moonbitstack/mooncat", ""),
      (schema_pkg, ""),
      (logic_pkg, ""),
    ],
    main=asgi_main(
      mod_, "GraphQL", "@moongql.graphql_app(@schema.build_schema(), @logic.resolvers(svc))",
    ),
  )
  out.push({
    path: at(dir, "internal/schema/moon.pkg"),
    content: pkg_file([gql]),
    regen: Always,
  })
  out.push({
    path: at(dir, "internal/schema/" + st.format("schema") + ".mbt"),
    content: @gql.generate_gql(spec),
    regen: Always,
  })
  let tests = pkg_file([gql, (config_pkg, ""), (schema_pkg, "")]).replace(
    old="}\n",
    new="} for \"test\"\n",
  )
  out.push({
    path: at(dir, "internal/logic/moon.pkg"),
    content: pkg_file([gql, (svc_pkg, "")]) + "\n" + tests,
    regen: Once,
  })
  out.push({
    path: at(dir, "internal/logic/" + st.format("resolvers") + ".mbt"),
    content: resolvers_src(spec),
    regen: Once,
  })
  let test_src =
    #|///|
    #|test "ping answers" {
    #|  let svc = @svc.ServiceContext::new(@config.Config::new())
    #|  let got = @moongql.execute(@schema.build_schema(), @logic.resolvers(svc), "{ ping }")
    #|  assert_eq(got, { "data": { "ping": "pong" } })
    #|}
  out.push({
    path: at(dir, "internal/logic/" + st.format("resolvers") + "_test.mbt"),
    content: test_src + "\n",
    regen: Once,
  })
  out
}
