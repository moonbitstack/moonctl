///|
/// SQL DDL → moonorm model + typed CRUD (goctl's `model mysql ddl`). `parse_ddl`
/// reads `CREATE TABLE` statements — column types, primary keys, `NOT NULL`, and
/// `DEFAULT` — and `generate_crud_from_ddl` emits, per table, the record struct, a
/// `@moonorm.Model`, an up/down migration, and parameterised CRUD: `insert`/`all`
/// always, plus `find_by_id`/`update`/`delete_by_id` when a table has a single-
/// column primary key (`users` does; `events` has none, so it gets only the pair).
///
///     moon run src/examples/05-ddl-crud
#coverage.skip
fn main {
  let source =
    #|CREATE TABLE users (
    #|  id     INTEGER PRIMARY KEY,
    #|  name   TEXT NOT NULL,
    #|  email  TEXT,
    #|  age    INTEGER DEFAULT 233,
    #|  active BOOLEAN DEFAULT 1
    #|);
    #|
    #|CREATE TABLE events (
    #|  ts      BIGINT NOT NULL,
    #|  payload BLOB,
    #|  score   REAL
    #|);
  let tables = @moonctl.parse_ddl(source)
  for t in tables {
    let cols = t.columns.map(fn(c) { c.name + ":" + c.type_ })
    println("table \{t.name} (\{cols.length()} cols): \{cols.join(", ")}")
  }
  println("\n==== generate_crud(parse_ddl(sql)) -> moonorm model + CRUD ====\n")
  let crud = @moonctl.generate_crud(tables)
  println(crud)

  // generate_crud_from_ddl is the one-step form: parse_ddl then generate_crud.
  println(
    "generate_crud(tables) == generate_crud_from_ddl(sql): \{crud == @moonctl.generate_crud_from_ddl(source)}",
  )
}
