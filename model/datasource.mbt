// Live-datasource schema reflection: read a running database's schema and generate
// the same moonorm data-access layer the `.sql` DDL front end produces. goctl's
// `model mysql datasource` / `model pg datasource` connects to a live server, reads
// its information-schema, and generates models; this is the MoonBit equivalent.
//
// The schema *reading* (a real DB round trip) is native and lives in the `reflect`
// sub-package. This file holds the pure, all-backend core — DSN parsing and the
// reflected-column → model pipeline — so it is unit-testable without a live database,
// and the native reader stays a thin adapter that only produces `ReflectedColumn`s.

///|
/// A PostgreSQL connection target parsed from a `postgres://` DSN.
pub(all) struct PgTarget {
  host : String
  port : Int32
  user : String
  password : String
  database : String
}

///|
/// A parsed datasource DSN: which backend to read, and how to reach it.
pub(all) enum DataSource {
  Sqlite(String) // a file path, or ":memory:"
  Postgres(PgTarget)
}

///|
/// Raised when a DSN string cannot be parsed into a `DataSource`.
pub suberror DataSourceError {
  BadDsn(String)
}

///|
impl Show for DataSourceError with fn output(self, logger) {
  match self {
    BadDsn(m) => logger.write_string("bad datasource DSN: " + m)
  }
}

///|
/// Index of the last `ch` in `s`, or `-1` if absent.
fn rindex_of(s : String, ch : UInt16) -> Int32 {
  let mut idx = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ch {
      idx = i
    }
  }
  idx
}

///|
/// The leading token of `s` up to the first whitespace or `(` — the bare type
/// keyword of a column type like `VARCHAR(255)` or `double precision`.
fn type_head(s : String) -> String {
  let n = s.length()
  for i = 0; i < n; i = i + 1 {
    if @text.is_ws(s[i]) || s[i] == '(' {
      return s[0:i].to_owned()
    }
  }
  s
}

///|
/// Parse a run of ASCII digits into an `Int`, or fall back to `dflt` when the text
/// is empty or non-numeric (a malformed port keeps the default rather than failing
/// the whole DSN).
fn parse_uint(s : String, dflt : Int32) -> Int32 {
  let n = s.length()
  if n == 0 {
    return dflt
  }
  let mut v = 0
  for i = 0; i < n; i = i + 1 {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      return dflt
    }
    v = v * 10 + (c - 0x30)
  }
  v
}

///|
/// Parse a datasource DSN into a `DataSource`. Recognised forms:
///
/// - SQLite: `sqlite:PATH`, `sqlite://PATH`, `sqlite3:PATH`, `file:PATH`,
///   the literal `:memory:`, or a bare path ending in `.db` / `.sqlite` / `.sqlite3`.
/// - PostgreSQL: `postgres://[user[:password]@]host[:port][/database][?…]` (and the
///   `postgresql://` spelling). The port defaults to `5432`, the user to `postgres`;
///   the database name is required.
///
/// Raises `BadDsn` on an unrecognised scheme or a PostgreSQL URL missing its host or
/// database.
pub fn parse_dsn(dsn : String) -> DataSource raise DataSourceError {
  let d = @text.trim(dsn)
  if d == "" {
    raise BadDsn("empty DSN")
  }
  if @text.starts_with(d, "postgresql://") {
    parse_pg(d[13:].to_owned())
  } else if @text.starts_with(d, "postgres://") {
    parse_pg(d[11:].to_owned())
  } else if @text.starts_with(d, "sqlite3://") {
    Sqlite(d[10:].to_owned())
  } else if @text.starts_with(d, "sqlite://") {
    Sqlite(d[9:].to_owned())
  } else if @text.starts_with(d, "sqlite3:") {
    Sqlite(d[8:].to_owned())
  } else if @text.starts_with(d, "sqlite:") {
    Sqlite(d[7:].to_owned())
  } else if @text.starts_with(d, "file:") {
    Sqlite(d[5:].to_owned())
  } else if d == ":memory:" ||
    @text.ends_with(d, ".db") ||
    @text.ends_with(d, ".sqlite") ||
    @text.ends_with(d, ".sqlite3") {
    Sqlite(d)
  } else {
    raise BadDsn(
      "unrecognised DSN scheme: " +
      dsn +
      " (expected sqlite:PATH or postgres://…)",
    )
  }
}

///|
/// Parse the authority of a `postgres://` DSN (everything after the scheme).
fn parse_pg(rest : String) -> DataSource raise DataSourceError {
  let q = @api.index_of(rest, '?', 0)
  let body = if q >= 0 { rest[0:q].to_owned() } else { rest }
  let at = rindex_of(body, '@')
  let mut user = "postgres"
  let mut password = ""
  let authority = if at >= 0 {
    let userinfo = body[0:at].to_owned()
    let colon = @api.index_of(userinfo, ':', 0)
    if colon >= 0 {
      user = userinfo[0:colon].to_owned()
      password = userinfo[colon + 1:].to_owned()
    } else if userinfo != "" {
      user = userinfo
    }
    body[at + 1:].to_owned()
  } else {
    body
  }
  let slash = @api.index_of(authority, '/', 0)
  let hostport = if slash >= 0 {
    authority[0:slash].to_owned()
  } else {
    authority
  }
  let database = if slash >= 0 { authority[slash + 1:].to_owned() } else { "" }
  let pc = @api.index_of(hostport, ':', 0)
  let host = if pc >= 0 { hostport[0:pc].to_owned() } else { hostport }
  let port = if pc >= 0 {
    parse_uint(hostport[pc + 1:].to_owned(), 5432)
  } else {
    5432
  }
  if host == "" {
    raise BadDsn("postgres DSN has no host: " + rest)
  }
  if database == "" {
    raise BadDsn("postgres DSN has no database name: " + rest)
  }
  Postgres({ host, port, user, password, database, })
}

///|
/// One column of a reflected database schema: the `table` it belongs to, its
/// `name`, its raw SQL type text (`INTEGER`, `character varying`, `VARCHAR(255)`, …),
/// and whether it is a primary key / accepts NULL. This is the neutral shape a live
/// reader (SQLite `PRAGMA table_info`, PostgreSQL `information_schema.columns`)
/// produces and `tables_from_reflection` folds into `DdlTable`s.
pub(all) struct ReflectedColumn {
  table : String
  name : String
  sql_type : String
  primary_key : Bool
  nullable : Bool
}

///|
/// Fold reflected columns into `DdlTable`s, grouping by table in first-seen order and
/// mapping each raw SQL type onto its MoonBit scalar (the leading type keyword drives
/// the mapping, so `character varying` and `VARCHAR(255)` both land on `String`). The
/// result feeds `generate_crud`, so a live schema and a `.sql` file reach the same
/// model generator.
pub fn tables_from_reflection(cols : Array[ReflectedColumn]) -> Array[DdlTable] {
  let order : Array[String] = []
  let tables : Map[String, DdlTable] = Map([])
  for c in cols {
    let t = match tables.get(c.table) {
      Some(t) => t
      None => {
        let t : DdlTable = { name: c.table, columns: [], }
        tables[c.table] = t
        order.push(c.table)
        t
      }
    }
    t.columns.push({
      name: c.name,
      type_: map_sql_type(type_head(c.sql_type).to_lower()),
      primary_key: c.primary_key,
      nullable: c.nullable,
      default_: None,
    })
  }
  let out : Array[DdlTable] = []
  for name in order {
    match tables.get(name) {
      Some(t) => out.push(t)
      None => ()
    }
  }
  out
}

///|
/// Generate a moonorm data-access layer (models + typed CRUD) straight from a live
/// schema's reflected columns — the in-memory counterpart of `generate_crud_from_ddl`.
/// The `reflect` sub-package produces the `ReflectedColumn`s from a real connection.
pub fn generate_crud_from_reflection(cols : Array[ReflectedColumn]) -> String {
  generate_crud(tables_from_reflection(cols))
}
