///|
/// Read every user table's columns from a live SQLite database and return them as
/// `@moonctl.ReflectedColumn`s, ready for `@moonctl.generate_crud_from_reflection`.
/// Tables are listed from `sqlite_master` (skipping SQLite's own `sqlite_*` tables),
/// and each table's columns come from `PRAGMA table_info` — its `name`, declared
/// `type`, `notnull` flag, and `pk` index. This is the SQLite half of goctl's
/// `model … datasource`.
///
/// The table name is interpolated into the `PRAGMA` (which cannot bind parameters);
/// it comes from `sqlite_master`, i.e. the database's own schema, not from user input.
pub fn reflect_sqlite(
  db : @sqlite.SqliteDriver,
) -> Array[@moonctl.ReflectedColumn] raise @moondb.DbError {
  let driver : &@moondb.Driver = db
  let names : Array[String] = []
  for
    row in driver.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      [],
    ) {
    names.push(row.text(0))
  }
  let cols : Array[@moonctl.ReflectedColumn] = []
  for name in names {
    for row in driver.query("PRAGMA table_info(\"" + name + "\")", []) {
      // SQLite's table_info reports notnull=0 for an `INTEGER PRIMARY KEY` (the rowid
      // alias), so treat a primary key as NOT NULL — matching how the `.sql` DDL front
      // end reads `PRIMARY KEY` and keeping both paths' models identical.
      let pk = row.int(5) > 0
      cols.push({
        table: name,
        name: row.text(1),
        sql_type: row.text(2),
        primary_key: pk,
        nullable: row.int(3) == 0 && !pk,
      })
    }
  }
  cols
}

///|
/// Read every table in the `public` schema of a live PostgreSQL database and return
/// its columns as `@moonctl.ReflectedColumn`s. The introspection joins
/// `information_schema.columns` against the primary-key columns from
/// `table_constraints` / `key_column_usage`, ordered by table and column position, so
/// column order and primary keys survive. This is the PostgreSQL half of goctl's
/// `model pg datasource`; it runs over `@pg.PgConn`'s async wire protocol, so call it
/// inside an event loop.
pub async fn reflect_postgres(
  conn : @pg.PgConn,
) -> Array[@moonctl.ReflectedColumn] raise @moondb.DbError {
  let sql = "SELECT c.table_name, c.column_name, c.data_type, c.is_nullable, " +
    "CASE WHEN pk.column_name IS NOT NULL THEN 'Y' ELSE 'N' END AS is_pk " +
    "FROM information_schema.columns c " +
    "LEFT JOIN (" +
    "SELECT kcu.table_name, kcu.column_name " +
    "FROM information_schema.table_constraints tc " +
    "JOIN information_schema.key_column_usage kcu " +
    "ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema " +
    "WHERE tc.constraint_type = 'PRIMARY KEY'" +
    ") pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name " +
    "WHERE c.table_schema = 'public' " +
    "ORDER BY c.table_name, c.ordinal_position"
  let cols : Array[@moonctl.ReflectedColumn] = []
  for row in conn.query(sql, []) {
    cols.push({
      table: row.text(0),
      name: row.text(1),
      sql_type: row.text(2),
      nullable: row.text(3) == "YES",
      primary_key: row.text(4) == "Y",
    })
  }
  cols
}
