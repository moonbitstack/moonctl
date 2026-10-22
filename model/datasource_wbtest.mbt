///|
/// The SQLite path of a parsed DSN, or `""` if it parsed to Postgres.
fn sqlite_path(d : DataSource) -> String {
  match d {
    Sqlite(p) => p
    Postgres(_) => ""
  }
}

///|
test "parse_dsn recognises every SQLite spelling" {
  assert_eq(sqlite_path(parse_dsn("sqlite:app.db")), "app.db")
  assert_eq(sqlite_path(parse_dsn("sqlite://data/app.db")), "data/app.db")
  assert_eq(sqlite_path(parse_dsn("sqlite3:app.db")), "app.db")
  assert_eq(sqlite_path(parse_dsn("sqlite3://app.db")), "app.db")
  assert_eq(sqlite_path(parse_dsn("file:/tmp/x.db")), "/tmp/x.db")
  assert_eq(sqlite_path(parse_dsn(":memory:")), ":memory:")
  assert_eq(sqlite_path(parse_dsn("bare.db")), "bare.db")
  assert_eq(sqlite_path(parse_dsn("bare.sqlite")), "bare.sqlite")
  assert_eq(sqlite_path(parse_dsn("bare.sqlite3")), "bare.sqlite3")
  assert_eq(sqlite_path(parse_dsn("  spaced.db  ")), "spaced.db")
}

///|
test "parse_dsn parses a full Postgres URL" {
  match parse_dsn("postgres://alice:s3cret@db.example.com:6543/shop") {
    Postgres(t) => {
      assert_eq(t.user, "alice")
      assert_eq(t.password, "s3cret")
      assert_eq(t.host, "db.example.com")
      assert_eq(t.port, 6543)
      assert_eq(t.database, "shop")
    }
    Sqlite(_) => fail("expected Postgres")
  }
}

///|
test "parse_dsn applies Postgres defaults and the postgresql:// spelling" {
  match parse_dsn("postgresql://localhost/mydb") {
    Postgres(t) => {
      assert_eq(t.user, "postgres")
      assert_eq(t.password, "")
      assert_eq(t.host, "localhost")
      assert_eq(t.port, 5432)
      assert_eq(t.database, "mydb")
    }
    Sqlite(_) => fail("expected Postgres")
  }
}

///|
test "parse_dsn keeps a user with no password, and drops query params" {
  match parse_dsn("postgres://bob@10.0.0.5/db?sslmode=disable") {
    Postgres(t) => {
      assert_eq(t.user, "bob")
      assert_eq(t.password, "")
      assert_eq(t.host, "10.0.0.5")
      assert_eq(t.port, 5432)
      assert_eq(t.database, "db")
    }
    Sqlite(_) => fail("expected Postgres")
  }
}

///|
test "parse_dsn rejects malformed DSNs" {
  let bad = ["", "mysql://x/y", "postgres:///nodb", "postgres://host"]
  for dsn in bad {
    let raised = try {
      parse_dsn(dsn) |> ignore
      false
    } catch {
      BadDsn(_) => true
    }
    assert_eq(raised, true)
  }
}

///|
test "tables_from_reflection groups columns and maps SQL types" {
  let cols : Array[ReflectedColumn] = [
    {
      table: "users",
      name: "id",
      sql_type: "INTEGER",
      primary_key: true,
      nullable: false,
    },
    {
      table: "users",
      name: "name",
      sql_type: "VARCHAR(255)",
      primary_key: false,
      nullable: false,
    },
    {
      table: "users",
      name: "age",
      sql_type: "integer",
      primary_key: false,
      nullable: true,
    },
    {
      table: "posts",
      name: "id",
      sql_type: "bigint",
      primary_key: true,
      nullable: false,
    },
    {
      table: "posts",
      name: "body",
      sql_type: "character varying",
      primary_key: false,
      nullable: true,
    },
    {
      table: "posts",
      name: "score",
      sql_type: "double precision",
      primary_key: false,
      nullable: true,
    },
    {
      table: "posts",
      name: "ok",
      sql_type: "boolean",
      primary_key: false,
      nullable: true,
    },
    {
      table: "posts",
      name: "raw",
      sql_type: "bytea",
      primary_key: false,
      nullable: true,
    },
  ]
  let tables = tables_from_reflection(cols)
  assert_eq(tables.length(), 2)
  // first-seen table order preserved even though rows interleave by appearance
  assert_eq(tables[0].name, "users")
  assert_eq(tables[1].name, "posts")
  let users = tables[0]
  assert_eq(users.columns.length(), 3)
  assert_eq(users.columns[0].type_, "Int")
  assert_eq(users.columns[0].primary_key, true)
  assert_eq(users.columns[0].nullable, false)
  assert_eq(users.columns[1].type_, "String")
  assert_eq(users.columns[2].type_, "Int")
  assert_eq(users.columns[2].nullable, true)
  let posts = tables[1]
  assert_eq(posts.columns[0].type_, "Int64")
  assert_eq(posts.columns[1].type_, "String")
  assert_eq(posts.columns[2].type_, "Double")
  assert_eq(posts.columns[3].type_, "Bool")
  assert_eq(posts.columns[4].type_, "Bytes")
}

///|
test "generate_crud_from_reflection emits a model + typed CRUD" {
  let cols : Array[ReflectedColumn] = [
    {
      table: "widget",
      name: "id",
      sql_type: "INTEGER",
      primary_key: true,
      nullable: false,
    },
    {
      table: "widget",
      name: "label",
      sql_type: "TEXT",
      primary_key: false,
      nullable: false,
    },
  ]
  let code = generate_crud_from_reflection(cols)
  assert_eq(contains(code, "pub(all) struct Widget {"), true)
  assert_eq(contains(code, "widget_model : @moonorm.Model[Widget]"), true)
  assert_eq(contains(code, "pub fn widget_insert("), true)
  assert_eq(contains(code, "pub fn widget_find_by_id("), true)
  assert_eq(contains(code, "pub fn widget_up("), true)
}
