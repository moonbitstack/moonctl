///|
fn shelf() -> @api.Spec {
  let src =
    #|type Book {
    #|  title: string
    #|}
    #|
    #|service shelf {
    #|  get /books/:id get_book
    #|}
  @api.parse_lenient(src)
}

///|
test "the schema is generated, the resolvers are seeded" {
  let tree = generate_gql_tree(shelf())
  assert_eq(
    contains(tree_at(tree, "internal/schema/schema.mbt"), "DO NOT EDIT"),
    true,
  )
  let resolvers = tree_at(tree, "internal/logic/resolvers.mbt")
  assert_eq(contains(resolvers, "DO NOT EDIT"), false)
  assert_eq(
    contains(
      resolvers, "resolvers.field(\"Query\", \"book\", _ => Json::null())",
    ),
    true,
  )
}

///|
test "a second run rewrites the schema and keeps the resolvers" {
  let written = tree_plan(generate_gql_tree(shelf()), _ => true).map(f => f.path)
  assert_eq(written, ["internal/schema/moon.pkg", "internal/schema/schema.mbt"])
}

///|
test "the resolver test imports what it queries with" {
  let pkg = tree_at(generate_gql_tree(shelf()), "internal/logic/moon.pkg")
  assert_eq(contains(pkg, "\"shelf/internal/schema\",\n} for \"test\""), true)
}
