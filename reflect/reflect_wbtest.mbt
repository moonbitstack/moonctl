///|
/// Whether `needle` occurs in `haystack` (String has no `contains` over substrings
/// in scope here, so the test carries its own).
fn has(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
/// Reflect a real, live SQLite schema and generate models from it end to end: open a
/// private in-memory database, create two tables, read them back with
/// `reflect_sqlite`, and check the reflected columns and the generated moonorm layer.
test "reflect a live SQLite schema into models" {
  let drv = @sqlite.SqliteDriver::open(":memory:")
  drv.exec_script(
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER, score REAL);" +
    "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, blob_data BLOB);",
  )
  let cols = reflect_sqlite(drv)
  // users: 4 columns, then posts: 3 — sqlite_master lists them alphabetically, and
  // 'posts' sorts before 'users'.
  assert_eq(cols.length(), 7)
  assert_eq(cols[0].table, "posts")
  assert_eq(cols[3].table, "users")
  assert_eq(cols[3].name, "id")
  assert_eq(cols[3].sql_type, "INTEGER")
  assert_eq(cols[3].primary_key, true)
  assert_eq(cols[3].nullable, false)
  assert_eq(cols[4].name, "name")
  assert_eq(cols[4].primary_key, false)
  assert_eq(cols[4].nullable, false)
  assert_eq(cols[5].name, "age")
  assert_eq(cols[5].nullable, true)

  // The reflected columns generate a compilable moonorm data layer.
  let code = @moonctl.generate_crud_from_reflection(cols)
  assert_eq(has(code, "pub(all) struct Users {"), true)
  assert_eq(has(code, "id : Int"), true)
  assert_eq(has(code, "name : String"), true)
  assert_eq(has(code, "score : Double"), true)
  assert_eq(has(code, "users_model : @moonorm.Model[Users]"), true)
  assert_eq(has(code, "pub fn users_insert("), true)
  assert_eq(
    has(code, "pub fn users_find_by_id(sess : @moonorm.Session, id : Int32)"),
    true,
  )
  assert_eq(has(code, "pub(all) struct Posts {"), true)
  assert_eq(has(code, "blob_data : Bytes"), true)
}
