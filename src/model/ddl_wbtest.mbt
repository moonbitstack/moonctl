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
  // age INTEGER -> Int32, nullable
  assert_eq(t.columns[2].name, "age")
  assert_eq(t.columns[2].type_, "Int32")
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
    contains(code, "@moonorm.column(\"id\", IntType, primary_key=true),"),
    true,
  )
  assert_eq(
    contains(code, "@moonorm.column(\"name\", TextType, nullable=false),"),
    true,
  )
  assert_eq(contains(code, "@moonorm.column(\"active\", BoolType),"), true)
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
  assert_eq(map_sql_type("integer"), "Int32")
  assert_eq(map_sql_type("bigint"), "Int64")
  assert_eq(map_sql_type("text"), "String")
  assert_eq(map_sql_type("real"), "Double")
  assert_eq(map_sql_type("blob"), "Bytes")
  assert_eq(map_sql_type("boolean"), "Bool")
  // unknown falls back to a TEXT-affinity String
  assert_eq(map_sql_type("geography"), "String")
}

///|
/// A two-table schema carrying every constraint this front end reads: a
/// column-level `UNIQUE`, two `CREATE INDEX` statements (one of them unique and
/// declared before its table), a named table-level foreign key with a referential
/// action, and a column-level `REFERENCES`.
let related_ddl : String =
  #|CREATE UNIQUE INDEX uq_heroes_code ON heroes (code);
  #|CREATE INDEX ix_heroes_team ON heroes (team_id, code);
  #|
  #|CREATE TABLE teams (
  #|  id    INTEGER PRIMARY KEY,
  #|  name  TEXT NOT NULL UNIQUE
  #|);
  #|
  #|CREATE TABLE heroes (
  #|  id       INTEGER PRIMARY KEY,
  #|  team_id  INTEGER NOT NULL,
  #|  mentor   INTEGER REFERENCES heroes(id) ON DELETE SET NULL,
  #|  code     TEXT,
  #|  CONSTRAINT fk_hero_team FOREIGN KEY (team_id)
  #|    REFERENCES teams(id) ON DELETE CASCADE ON UPDATE RESTRICT
  #|);

///|
test "parse_ddl: CREATE INDEX, alone or after the table it covers" {
  let tables = parse_ddl(related_ddl)
  assert_eq(tables.length(), 2)
  let heroes = tables[1]
  assert_eq(heroes.name, "heroes")
  // both statements landed on the table, in the order they were written — even
  // though the first one came before the CREATE TABLE
  assert_eq(heroes.indexes.length(), 2)
  assert_eq(heroes.indexes[0].name, "uq_heroes_code")
  assert_eq(heroes.indexes[0].columns.length(), 1)
  assert_eq(heroes.indexes[0].columns[0], "code")
  assert_eq(heroes.indexes[0].unique, true)
  assert_eq(heroes.indexes[1].name, "ix_heroes_team")
  assert_eq(heroes.indexes[1].columns.join(","), "team_id,code")
  assert_eq(heroes.indexes[1].unique, false)
  // a table with none keeps none
  assert_eq(tables[0].indexes.length(), 0)
}

///|
test "parse_ddl: UNIQUE and KEY table constraints are indexes" {
  let src =
    #|CREATE TABLE tags (
    #|  id    INTEGER PRIMARY KEY,
    #|  slug  TEXT,
    #|  label TEXT,
    #|  UNIQUE (slug),
    #|  KEY ix_label (label)
    #|);
  let t = parse_ddl(src)[0]
  assert_eq(t.indexes.length(), 2)
  // an unnamed unique constraint stays unnamed, so the database names it
  assert_eq(t.indexes[0].name, "")
  assert_eq(t.indexes[0].unique, true)
  assert_eq(t.indexes[0].columns.join(","), "slug")
  assert_eq(t.indexes[1].name, "ix_label")
  assert_eq(t.indexes[1].unique, false)
}

///|
test "parse_ddl: a column UNIQUE is the column's, not the table's" {
  let t = parse_ddl(related_ddl)[0]
  assert_eq(t.indexes.length(), 0)
  assert_eq(t.columns[1].name, "name")
  assert_eq(t.columns[1].unique, true)
  assert_eq(t.columns[0].unique, false)
}

///|
test "parse_ddl: a table-level foreign key, with its actions" {
  let heroes = parse_ddl(related_ddl)[1]
  // two keys: the column-level one onto the table itself, the named table-level one
  assert_eq(heroes.foreign_keys.length(), 2)
  let team = heroes.foreign_keys[1]
  assert_eq(team.columns.join(","), "team_id")
  assert_eq(team.ref_table, "teams")
  assert_eq(team.ref_columns.join(","), "id")
  assert_eq(team.on_delete, "CASCADE")
  assert_eq(team.on_update, "RESTRICT")
}

///|
test "parse_ddl: a column-level REFERENCES" {
  let heroes = parse_ddl(related_ddl)[1]
  let mentor = heroes.foreign_keys[0]
  assert_eq(mentor.columns.join(","), "mentor")
  assert_eq(mentor.ref_table, "heroes")
  assert_eq(mentor.ref_columns.join(","), "id")
  // `SET NULL` is two words, and both are kept as the DDL wrote them
  assert_eq(mentor.on_delete, "SET NULL")
  assert_eq(mentor.on_update, "")
}

///|
test "generate_crud: the model declares its indexes and foreign keys" {
  let code = generate_crud(parse_ddl(related_ddl))
  // the index list is the model's, so `create_table` creates them
  assert_eq(
    contains(
      code, "indexes=[\n    @moonorm.index([\"code\"], name=\"uq_heroes_code\", unique=true),\n    @moonorm.index([\"team_id\", \"code\"], name=\"ix_heroes_team\"),\n  ],",
    ),
    true,
  )
  // a column UNIQUE is the column's
  assert_eq(contains(code, "unique=true"), true)
  // and a foreign key names its target on the column that holds it
  assert_eq(contains(code, ", references=(\"teams\", \"id\")"), true)
  assert_eq(contains(code, ", on_delete=\"CASCADE\""), true)
  assert_eq(contains(code, ", on_update=\"RESTRICT\""), true)
  assert_eq(contains(code, ", references=(\"heroes\", \"id\")"), true)
  // a table with no index declares none
  assert_eq(contains(code, "indexes=[]"), false)
}
