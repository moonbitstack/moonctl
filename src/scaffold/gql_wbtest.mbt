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
test "the schema is declared with annotations, not built by a program" {
  let tree = generate_gql_tree(shelf())
  let schema = tree_at(tree, "internal/schema/schema.mbt")
  // the type is a `#gql.type` struct
  assert_eq(contains(schema, "#gql.type\npub struct Book {"), true)
  assert_eq(contains(schema, "  title : String"), true)
  // the route is a root field, its URL segment the field's argument
  // the arguments are the URL segments, one per line
  assert_eq(
    contains(
      schema, "#gql.query\npub fn get_book(\n  id : String,\n) -> String",
    ),
    true,
  )
  assert_eq(contains(schema, "  ignore(id)"), true)
  // and nothing hand-builds the schema: moongql writes `register` from these
  assert_eq(contains(schema, "schema.object("), false)
  assert_eq(contains(schema, "resolvers.field("), false)
  // `build()` is what the entry point calls
  assert_eq(
    contains(schema, "pub fn build() -> (@moongql.Schema, @moongql.Resolvers)"),
    true,
  )
  assert_eq(contains(schema, "  register(schema, resolvers)"), true)
}

///|
test "the module carries the rule that turns the annotations into register" {
  let tree = generate_gql_tree(shelf())
  let mod_ = tree_at(tree, "moon.mod")
  assert_eq(contains(mod_, "name = \"shelf\""), true)
  assert_eq(contains(mod_, "moonx moonbitstack/moongql/cmd/gql@"), true)
  let pkg = tree_at(tree, "internal/schema/moon.pkg")
  assert_eq(
    contains(
      pkg, "dev_build(rule: \"gql\", input: \"schema.mbt\", output: \"schema.g.mbt\")",
    ),
    true,
  )
  // the generated file is the generator's, not the formatter's
  assert_eq(contains(pkg, "formatter(ignore: [ \"schema.g.mbt\" ])"), true)
}

///|
test "the schema is the author's file: a second run keeps it" {
  // the resolvers live in the same file as the types, so it is seeded once; the
  // `register` beside it is regenerated on every build, which is what keeps it in
  // step with the annotations
  let written = tree_plan(generate_gql_tree(shelf()), _ => true).map(f => f.path)
  assert_eq(written, [])
}

///|
test "a test is seeded that stays true once the stubs are filled in" {
  let tree = generate_gql_tree(shelf())
  let seeded = tree_at(tree, "internal/schema/schema_test.mbt")
  assert_eq(contains(seeded, "@schema.build()"), true)
  assert_eq(contains(seeded, "{ __typename }"), true)
  // a service with no query route has no `Query` type to ask for one on
  let only_post = @api.parse_lenient(
    "service shelf {\n  post /books add_book\n}\n",
  )
  let tree = generate_gql_tree(only_post)
  assert_eq(tree.any(f => f.path == "internal/schema/schema_test.mbt"), false)
}

///|
test "the entry point builds the schema and serves it" {
  let tree = generate_gql_tree(shelf())
  let main = tree_at(tree, "shelf.mbt")
  assert_eq(contains(main, "let (schema, resolvers) = @schema.build()"), true)
  assert_eq(contains(main, "@moongql.graphql_app(schema, resolvers)"), true)
  // the resolvers are free functions, so there is no context to thread
  assert_eq(tree.any(f => f.path == "internal/svc/service_context.mbt"), false)
  assert_eq(contains(tree_at(tree, "moon.pkg"), "internal/svc"), false)
}

///|
test "Bytes and Map fields are carried by the scalars that name them" {
  let spec = @api.parse_lenient(
    (
      #|type Blob {
      #|  id: int64
      #|  data: bytes
      #|  meta: map[string]string
      #|}
      #|
      #|service shelf {
      #|  get /blobs/:id get_blob
      #|}
    ),
  )
  let tree = generate_gql_tree(spec)
  let schema = tree_at(tree, "internal/schema/schema.mbt")
  assert_eq(contains(schema, "  id : Int64"), true)
  // `Bytes` has no `ToGql` impl this generator may write — the trait and the type
  // both belong elsewhere — so the field is declared as the text of the `Base64`
  // scalar, and the conversion comes with the schema.
  assert_eq(
    contains(
      schema, "  /// The base64 text of `data`, which is what the `Base64` scalar carries.\n  #gql.field(kind=\"Base64\")\n  data : String",
    ),
    true,
  )
  // a map is the object of the `JSON` scalar, for the same reason
  assert_eq(contains(schema, "#gql.field(kind=\"JSON\")\n  meta : Json"), true)
  // nothing is dropped, so nothing is reported
  assert_eq(gql_dropped_fields(spec).length(), 0)
  // the conversions the two scalars need are generated beside the schema, and the
  // package imports the encoder they call
  let scalars = tree_at(tree, "internal/schema/scalars.mbt")
  assert_eq(
    contains(scalars, "pub fn base64_of(bytes : Bytes) -> String"),
    true,
  )
  assert_eq(
    contains(scalars, "pub fn bytes_of_base64(text : String) -> Bytes?"),
    true,
  )
  let pkg = tree_at(tree, "internal/schema/moon.pkg")
  assert_eq(contains(pkg, "\"moonbitstack/moonbase/base64\""), true)
  assert_eq(contains(tree_at(tree, "moon.mod"), "moonbitstack/moonbase@"), true)
}

///|
test "a map whose key is not a string is left out, and said so" {
  let spec = @api.parse_lenient(
    (
      #|type Counts {
      #|  by_id: map[int]int
      #|}
      #|
      #|service shelf {
      #|  get /counts get_counts
      #|}
    ),
  )
  // an object's member names are strings, so an `Int` key has no shape to become
  assert_eq(gql_dropped_fields(spec), ["Counts.by_id (Map[Int32, Int32])"])
  let schema = tree_at(generate_gql_tree(spec), "internal/schema/schema.mbt")
  assert_eq(contains(schema, "by_id"), false)
}

///|
test "a streaming route is a subscription, one event per declared type" {
  let spec = @api.parse_lenient(
    (
      #|type Tick {
      #|  at: int64
      #|}
      #|
      #|service feed {
      #|  @handler watch
      #|  get /watch returns (stream Tick)
      #|}
    ),
  )
  let schema = tree_at(generate_gql_tree(spec), "internal/schema/schema.mbt")
  assert_eq(
    contains(
      schema, "#gql.subscription\npub fn watch() -> Array[Tick] {\n  []\n}",
    ),
    true,
  )
  // the event type is the declared one, not a string
  assert_eq(contains(schema, "Array[String]"), false)
}

///|
test "a route that declares a reply type returns it, optionally" {
  let spec = @api.parse_lenient(
    (
      #|type Book {
      #|  title: string
      #|}
      #|
      #|service shelf {
      #|  @handler get_book
      #|  get /books/:id returns (Book)
      #|}
    ),
  )
  let schema = tree_at(generate_gql_tree(spec), "internal/schema/schema.mbt")
  assert_eq(
    contains(schema, "pub fn get_book(\n  id : String,\n) -> Book?"),
    true,
  )
  // a typed reply has no stub value of its own
  assert_eq(contains(schema, "  None"), true)
}

///|
test "a route whose request type declares fields takes them as arguments" {
  let spec = @api.parse_lenient(
    (
      #|type PageReq {
      #|  page: int `form:"page"`
      #|  tag?: string
      #|}
      #|
      #|service shelf {
      #|  @handler list_books
      #|  get /books (PageReq)
      #|}
    ),
  )
  let schema = tree_at(generate_gql_tree(spec), "internal/schema/schema.mbt")
  assert_eq(
    contains(
      schema, "pub fn list_books(\n  page : Int32,\n  tag : String?,\n) -> String",
    ),
    true,
  )
}

///|
test "two routes under one handler get one root field each" {
  let spec = @api.parse_lenient(
    (
      #|service shelf {
      #|  @handler dup
      #|  get /a
      #|
      #|  @handler dup
      #|  get /b
      #|}
    ),
  )
  let schema = tree_at(generate_gql_tree(spec), "internal/schema/schema.mbt")
  assert_eq(contains(schema, "pub fn dup() -> String"), true)
  assert_eq(contains(schema, "pub fn dup_2() -> String"), true)
}
