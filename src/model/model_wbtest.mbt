///|
test "storable type: struct, model, table descriptor, migration" {
  let src =
    #|type User {
    #|  id:    int64
    #|  name:  string
    #|  admin: bool
    #|  score: float64
    #|  data:  bytes
    #|}
  let code = generate_model(@api.parse(src))
  assert_eq(contains(code, "DO NOT EDIT"), true)
  // struct
  assert_eq(contains(code, "pub(all) struct User {"), true)
  assert_eq(contains(code, "  id : Int64"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(contains(code, "  admin : Bool"), true)
  assert_eq(contains(code, "  score : Double"), true)
  assert_eq(contains(code, "  data : Bytes"), true)
  // model + columns (an `id` column is the primary key)
  assert_eq(
    contains(
      code, "pub let user_model : @moonorm.Model[User] = @moonorm.Model::new(",
    ),
    true,
  )
  assert_eq(
    contains(code, "@moonorm.column(\"id\", IntType, primary_key=true),"),
    true,
  )
  assert_eq(contains(code, "@moonorm.column(\"name\", TextType),"), true)
  assert_eq(contains(code, "@moonorm.column(\"admin\", BoolType),"), true)
  assert_eq(contains(code, "@moonorm.column(\"score\", RealType),"), true)
  assert_eq(contains(code, "@moonorm.column(\"data\", BlobType),"), true)
  // from_row decoder, projection order
  assert_eq(contains(code, "    id: row.int64(0),"), true)
  assert_eq(contains(code, "    name: row.text(1),"), true)
  assert_eq(contains(code, "    admin: row.bool(2),"), true)
  assert_eq(contains(code, "    score: row.double(3),"), true)
  assert_eq(contains(code, "    data: row.blob(4),"), true)
  // to_columns projection
  assert_eq(contains(code, "    (\"id\", @moondb.Int64(r.id)),"), true)
  assert_eq(contains(code, "    (\"name\", @moondb.Text(r.name)),"), true)
  assert_eq(contains(code, "    (\"admin\", @moondb.Bool(r.admin)),"), true)
  assert_eq(contains(code, "    (\"score\", @moondb.Double(r.score)),"), true)
  assert_eq(contains(code, "    (\"data\", @moondb.Blob(r.data)),"), true)
  // table descriptor via the model
  assert_eq(
    contains(
      code, "pub let user_table : @moonorm.Table = user_model.table_descriptor()",
    ),
    true,
  )
  // migration up/down
  assert_eq(
    contains(
      code, "pub fn user_up(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {",
    ),
    true,
  )
  assert_eq(
    contains(code, "sess.create_table(user_model, if_not_exists=true)"),
    true,
  )
  assert_eq(
    contains(
      code, "pub fn user_down(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {",
    ),
    true,
  )
  assert_eq(
    contains(code, "sess.execute(\"DROP TABLE IF EXISTS user\", [])"),
    true,
  )
}

///|
test "plain int maps to IntType via row.int / @moondb.Int" {
  let src =
    #|type Counter {
    #|  n: int
    #|}
  let code = generate_model(@api.parse(src))
  assert_eq(contains(code, "@moonorm.column(\"n\", IntType),"), true)
  assert_eq(contains(code, "    n: row.int(0),"), true)
  assert_eq(contains(code, "    (\"n\", @moondb.Int(r.n)),"), true)
  // no `id` column here -> primary_key is not forced on
  assert_eq(contains(code, "primary_key=true"), false)
}

///|
test "table name and columns are snake-cased" {
  let src =
    #|type BlogPost {
    #|  postID:     int64
    #|  authorName: string
    #|}
  let code = generate_model(@api.parse(src))
  assert_eq(
    contains(code, "pub let blog_post_model : @moonorm.Model[BlogPost]"),
    true,
  )
  assert_eq(contains(code, "@moonorm.column(\"post_id\", IntType),"), true)
  assert_eq(contains(code, "@moonorm.column(\"author_name\", TextType),"), true)
  // the struct field is snake-cased too, so the decoder and the projection read
  // the one name — `postID : Int64` is a MoonBit field, `PostID : Int64` is not
  assert_eq(contains(code, "  post_id : Int64"), true)
  assert_eq(contains(code, "    post_id: row.int64(0),"), true)
  assert_eq(
    contains(code, "    (\"post_id\", @moondb.Int64(r.post_id)),"),
    true,
  )
  assert_eq(contains(code, "postID"), false)
  assert_eq(
    contains(code, "sess.execute(\"DROP TABLE IF EXISTS blog_post\", [])"),
    true,
  )
}

///|
test "the struct, the model and the document spell one field the same way" {
  let src =
    #|type Account {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|service greet {
    #|  @handler create
    #|  post /accounts (Account)
    #|}
  let spec = @api.parse(src)
  // MoonBit refuses an upper-case struct field, so every generated MoonBit name is
  // the one snake-cased spelling
  assert_eq(contains(@gen.generate(spec), "  user_name : String"), true)
  let model = generate_model(spec)
  assert_eq(contains(model, "  user_name : String"), true)
  assert_eq(contains(model, "@moonorm.column(\"user_name\", TextType)"), true)
  assert_eq(contains(model, "    user_name: row.text(0),"), true)
  assert_eq(
    contains(model, "    (\"user_name\", @moondb.Text(r.user_name)),"),
    true,
  )
  assert_eq(contains(model, "UserName"), false)
  // and the wire side is what the json tag asked for
  let doc = @doc.openapi_document(spec, version=OpenApi31).stringify()
  assert_eq(contains(doc, "\"user_name\""), true)
  assert_eq(contains(doc, "UserName"), false)
}

///|
test "a block no table can hold still lists its columns the MoonBit way" {
  let code = generate_model(
    @api.parse("type Odd {\n  postID: int64\n  tags:   []string\n}"),
  )
  assert_eq(contains(code, "  post_id : Int64"), true)
  assert_eq(contains(code, "[\"post_id\", \"tags\"]"), true)
  assert_eq(contains(code, "postID"), false)
}

///|
test "an embedded block's fields reach the model too" {
  let src =
    #|type Base {
    #|  id: int64
    #|}
    #|
    #|type User {
    #|  Base
    #|  name: string
    #|}
  let code = generate_model(@api.parse(src))
  assert_eq(
    contains(code, "pub(all) struct User {\n  id : Int64\n  name : String\n}"),
    true,
  )
  assert_eq(
    contains(code, "@moonorm.column(\"id\", IntType, primary_key=true),"),
    true,
  )
  assert_eq(contains(code, "    name: row.text(1),"), true)
}

///|
test "non-storable field: struct + table descriptor, no model or migration" {
  let src =
    #|type Doc {
    #|  id:   int64
    #|  tags: []string
    #|}
  let code = generate_model(@api.parse(src))
  assert_eq(contains(code, "pub(all) struct Doc {"), true)
  assert_eq(contains(code, "  tags : Array[String]"), true)
  // a []string has no single-column storage class -> only the descriptor
  assert_eq(contains(code, "pub let doc_table : @moonorm.Table = {"), true)
  assert_eq(contains(code, "columns: [\"id\", \"tags\"],"), true)
  assert_eq(contains(code, "@moonorm.Model::new"), false)
  assert_eq(contains(code, "doc_up("), false)
}
