///|
/// Live-datasource reflection — the pure, all-backend core of `mctl model
/// datasource`. `parse_dsn` reads a SQLite or PostgreSQL DSN into a `DataSource`;
/// the native `reflect` sub-package then reads the running schema into a list of
/// `ReflectedColumn`. Here that list is supplied directly (no live DB), then
/// `tables_from_reflection` folds it into tables — mapping each raw SQL type onto
/// its MoonBit scalar, so `character varying` and `INTEGER` both land right — and
/// `generate_crud_from_reflection` runs it through the same generator the `.sql`
/// front end uses, so a live schema and a `.sql` file yield an identical model.
///
///     moon run src/examples/06-datasource
#coverage.skip
fn main {
  for dsn in ["sqlite:shop.db", "postgres://heke1228:qwe@localhost:5432/shop"] {
    let target = try {
      match @moonctl.parse_dsn(dsn) {
        Sqlite(path) => "Sqlite(\{path})"
        Postgres(t) => "Postgres(\{t.user}@\{t.host}:\{t.port}/\{t.database})"
      }
    } catch {
      _ => "bad DSN"
    }
    println("\{dsn}  ->  \{target}")
  }
  println("")

  // What the reflect sub-package hands back after reading a live schema.
  let cols : Array[@moonctl.ReflectedColumn] = [
    {
      table: "account",
      name: "id",
      sql_type: "INTEGER",
      primary_key: true,
      nullable: false,
    },
    {
      table: "account",
      name: "handle",
      sql_type: "character varying",
      primary_key: false,
      nullable: false,
    },
    {
      table: "account",
      name: "balance",
      sql_type: "BIGINT",
      primary_key: false,
      nullable: true,
    },
  ]
  for t in @moonctl.tables_from_reflection(cols) {
    let cs = t.columns.map(fn(c) { c.name + ":" + c.type_ })
    println("reflected table \{t.name}: \{cs.join(", ")}")
  }
  println(
    "\n==== generate_crud_from_reflection(cols) -> moonorm model + CRUD ====\n",
  )
  println(@moonctl.generate_crud_from_reflection(cols))
}
