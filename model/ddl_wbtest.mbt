///|
/// The DDL fixture reused across the parse and codegen assertions.
let sample_ddl : String =
  #|CREATE TABLE users (
  #|  id       BIGINT PRIMARY KEY,
  #|  name     VARCHAR(255) NOT NULL,
  #|  age      INTEGER,
  #|  active   BOOLEAN DEFAULT 1,
  #|  rating   REAL,
  #|  avatar   BLOB
  #|);

///|
test "parse_ddl: columns, types, primary key, nullability" {
  let tables = parse_ddl(sample_ddl)
  assert_eq(tables.length(), 1)
  let t = tables[0]
  assert_eq(t.name, "users")
  assert_eq(t.columns.length(), 6)
  // id BIGINT PRIMARY KEY -> Int64, pk, not null
  assert_eq(t.columns[0].name, "id")
  assert_eq(t.columns[0].type_, "Int64")
  assert_eq(t.columns[0].primary_key, true)
  assert_eq(t.columns[0].nullable, false)
  // name VARCHAR(255) NOT NULL -> String, not null, size skipped
  assert_eq(t.columns[1].name, "name")
  assert_eq(t.columns[1].type_, "String")
  assert_eq(t.columns[1].primary_key, false)
  assert_eq(t.columns[1].nullable, false)
  // age INTEGER -> Int, nullable
  assert_eq(t.columns[2].name, "age")
  assert_eq(t.columns[2].type_, "Int")
  assert_eq(t.columns[2].nullable, true)
  // active BOOLEAN DEFAULT 1 -> Bool, default captured
  assert_eq(t.columns[3].name, "active")
  assert_eq(t.columns[3].type_, "Bool")
  assert_eq(t.columns[3].default_, Some("1"))
  // rating REAL -> Double ; avatar BLOB -> Bytes
  assert_eq(t.columns[4].type_, "Double")
  assert_eq(t.columns[5].type_, "Bytes")
}

///|
test "parse_ddl: IF NOT EXISTS, quoted names, table-level primary key" {
  let src =
    #|CREATE TABLE IF NOT EXISTS `blog_posts` (
    #|  post_id     INTEGER,
    #|  author_name TEXT NOT NULL,
    #|  PRIMARY KEY (post_id)
    #|);
  let tables = parse_ddl(src)
  assert_eq(tables.length(), 1)
  let t = tables[0]
  assert_eq(t.name, "blog_posts")
  // table-level PRIMARY KEY (post_id) flips the column's flag
  assert_eq(t.columns.length(), 2)
  assert_eq(t.columns[0].name, "post_id")
  assert_eq(t.columns[0].primary_key, true)
  assert_eq(t.columns[1].primary_key, false)
}

///|
test "parse_ddl: multiple tables, comments, constraints skipped" {
  let src =
    #|-- users table
    #|CREATE TABLE users (
    #|  id INTEGER PRIMARY KEY,
    #|  team_id INTEGER,
    #|  FOREIGN KEY (team_id) REFERENCES teams(id),
    #|  UNIQUE (id)
    #|);
    #|/* second table */
    #|CREATE TABLE teams (
    #|  id INTEGER PRIMARY KEY
    #|);
  let tables = parse_ddl(src)
  assert_eq(tables.length(), 2)
  // constraints do not add phantom columns
  assert_eq(tables[0].columns.length(), 2)
  assert_eq(tables[1].name, "teams")
  assert_eq(tables[1].columns.length(), 1)
}

///|
test "generate_crud: struct, model, migration, typed CRUD shape" {
  let code = generate_crud(parse_ddl(sample_ddl))
  assert_eq(contains(code, "DO NOT EDIT"), true)
  // struct with the SQL columns
  assert_eq(contains(code, "pub(all) struct Users {"), true)
  assert_eq(contains(code, "  id : Int64"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(contains(code, "  active : Bool"), true)
  assert_eq(contains(code, "  avatar : Bytes"), true)
  // model with declared columns
  assert_eq(
    contains(
      code, "pub let users_model : @moonorm.Model[Users] = @moonorm.Model::new(",
    ),
    true,
  )
  assert_eq(
    contains(
      code, "@moonorm.column(\"id\", @moonorm.IntType, primary_key=true),",
    ),
    true,
  )
  assert_eq(
    contains(
      code, "@moonorm.column(\"name\", @moonorm.TextType, nullable=false),",
    ),
    true,
  )
  assert_eq(
    contains(code, "@moonorm.column(\"active\", @moonorm.BoolType),"),
    true,
  )
  // from_row + to_columns
  assert_eq(contains(code, "    id: row.int64(0),"), true)
  assert_eq(contains(code, "    active: row.bool(3),"), true)
  assert_eq(contains(code, "    (\"avatar\", @moondb.Blob(r.avatar)),"), true)
  // migration
  assert_eq(
    contains(code, "sess.create_table(users_model, if_not_exists=true)"),
    true,
  )
  assert_eq(
    contains(code, "sess.execute(\"DROP TABLE IF EXISTS users\", [])"),
    true,
  )
}

///|
test "generate_crud: parameterised CRUD statements keyed on the primary key" {
  let code = generate_crud(parse_ddl(sample_ddl))
  // find_by_id binds the id, never splices it
  assert_eq(
    contains(
      code, "pub fn users_find_by_id(sess : @moonorm.Session, id : Int64) -> Users?",
    ),
    true,
  )
  assert_eq(
    contains(
      code, "users_model.select().where_(\"id\", \"=\", @moondb.Int64(id)).limit(1)",
    ),
    true,
  )
  // insert / all through the session helpers
  assert_eq(contains(code, "sess.insert_record(users_model, record)"), true)
  assert_eq(contains(code, "sess.all(users_model)"), true)
  // delete_by_id binds the id
  assert_eq(
    contains(
      code, "sess.remove(@moonorm.delete(\"users\").where_(\"id\", \"=\", @moondb.Int64(id)))",
    ),
    true,
  )
  // update SETs every non-key column and keys on the pk, all bound
  assert_eq(
    contains(
      code, "@moonorm.update(\"users\").set(\"name\", @moondb.Text(record.name))",
    ),
    true,
  )
  assert_eq(
    contains(code, ".where_(\"id\", \"=\", @moondb.Int64(record.id))"),
    true,
  )
  // the primary key column is not in the SET list
  assert_eq(contains(code, ".set(\"id\", @moondb.Int64(record.id))"), false)
}

///|
test "generate_crud: no primary key -> insert/all only, no by-id helpers" {
  let src =
    #|CREATE TABLE events (
    #|  kind TEXT,
    #|  payload TEXT
    #|);
  let code = generate_crud(parse_ddl(src))
  assert_eq(contains(code, "pub fn events_insert("), true)
  assert_eq(contains(code, "pub fn events_all("), true)
  assert_eq(contains(code, "events_find_by_id"), false)
  assert_eq(contains(code, "events_update"), false)
  assert_eq(contains(code, "events_delete_by_id"), false)
}

///|
test "map_sql_type: the full type set the batch requires" {
  assert_eq(map_sql_type("integer"), "Int")
  assert_eq(map_sql_type("bigint"), "Int64")
  assert_eq(map_sql_type("text"), "String")
  assert_eq(map_sql_type("real"), "Double")
  assert_eq(map_sql_type("blob"), "Bytes")
  assert_eq(map_sql_type("boolean"), "Bool")
  // unknown falls back to a TEXT-affinity String
  assert_eq(map_sql_type("geography"), "String")
}
