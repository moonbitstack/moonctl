///|
test "generate_gql maps type blocks to a moongql schema" {
  let src =
    #|type User {
    #|  id:   int64
    #|  name: string
    #|  tags: []string
    #|}
    #|
    #|service greet {
    #|  get /users/:id get_user
    #|}
  let code = generate_gql(@api.parse(src))
  assert_eq(code.contains("pub fn build_schema() -> @moongql.Schema"), true)
  assert_eq(code.contains("let user = schema.object(\"User\")"), true)
  assert_eq(code.contains("user.field(\"id\", NonNull(Scalar(\"Int\")))"), true)
  assert_eq(
    code.contains("user.field(\"name\", NonNull(Scalar(\"String\")))"),
    true,
  )
  // []string -> a non-null list of non-null strings.
  assert_eq(
    code.contains(
      "user.field(\"tags\", NonNull(ListOf(NonNull(Scalar(\"String\")))))",
    ),
    true,
  )
}

///|
test "generate_gql adds ping and a Query lookup per type, and no resolvers" {
  let src =
    #|type Post {
    #|  title: string
    #|}
    #|
    #|service blog {
    #|  get /posts/:id get_post
    #|}
  let code = generate_gql(@api.parse(src))
  assert_eq(
    code.contains(
      "query.field_args(\"post\", [(\"id\", NonNull(Scalar(\"ID\")))], Named(\"Post\"))",
    ),
    true,
  )
  assert_eq(
    code.contains("query.field(\"ping\", NonNull(Scalar(\"String\")))"),
    true,
  )
  assert_eq(code.contains("resolvers"), false)
}

///|
test "generate_gql names a field on the wire, embeds and all" {
  let src =
    #|type Base {
    #|  id: int64 `json:"id"`
    #|}
    #|
    #|type User {
    #|  Base
    #|  UserName string `json:"user_name"`
    #|}
  let code = generate_gql(@api.parse(src))
  // the embedded field belongs to the type that inlined it
  assert_eq(code.contains("user.field(\"id\", NonNull(Scalar(\"Int\")))"), true)
  assert_eq(
    code.contains("user.field(\"user_name\", NonNull(Scalar(\"String\")))"),
    true,
  )
  assert_eq(code.contains("UserName"), false)
}

///|
test "generate_gql maps a named field type to a Named reference" {
  let src =
    #|type Team {
    #|  owner: User
    #|}
    #|
    #|service org {
    #|  get /teams/:id get_team
    #|}
  let code = generate_gql(@api.parse(src))
  assert_eq(code.contains("owner\", NonNull(Named(\"User\")))"), true)
}
