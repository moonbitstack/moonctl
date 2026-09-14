// The `model` sub-command's SQL front end: parse a `CREATE TABLE` DDL and emit a
// moonorm data-access layer for it. goctl reads a live MySQL/Postgres schema (or a
// `.sql` file) and generates a model with typed CRUD; this is the `.sql`-file half
// of that, transliterated. The generated code compiles against moonbitstack/moonorm +
// moonbitstack/moondb, and its statements are all parameterised, so a generated CRUD call
// is injection-safe by construction.

///|
/// One parsed column of a `CREATE TABLE` statement: the SQL column `name`, the
/// MoonBit `type_` its SQL type maps to (`Int`/`Int64`/`String`/`Double`/`Bool`/
/// `Bytes`), whether it is a primary key, whether it accepts NULL, and its literal
/// `DEFAULT` clause if any (kept as source text — it is emitted into DDL comments,
/// never bound).
pub(all) struct DdlColumn {
  name : String
  type_ : String
  mut primary_key : Bool
  nullable : Bool
  default_ : String?
}

///|
/// A parsed `CREATE TABLE`: the SQL table `name` and its ordered `columns`.
pub(all) struct DdlTable {
  name : String
  columns : Array[DdlColumn]
}

///|
/// Map a SQL column type keyword onto the MoonBit scalar it round-trips as. The set
/// the `.api` model generator already handles (`Int`/`Int64`/`String`/`Double`/
/// `Bool`/`Bytes`), reached from the SQL side: `INTEGER`/`BIGINT` → `Int`/`Int64`,
/// `TEXT` → `String`, `REAL` → `Double`, `BLOB` → `Bytes`, `BOOLEAN` → `Bool`, with
/// the common vendor spellings folded in. An unknown type falls back to `String`
/// (SQLite gives an undeclared column TEXT-ish affinity), so an exotic type still
/// produces a compilable model rather than failing the whole file.
fn map_sql_type(t : String) -> String {
  match t {
    "integer"
    | "int"
    | "int4"
    | "int2"
    | "smallint"
    | "tinyint"
    | "mediumint"
    | "serial" => "Int"
    "bigint" | "int8" | "bigserial" => "Int64"
    "text"
    | "varchar"
    | "char"
    | "character"
    | "varying"
    | "clob"
    | "string"
    | "nvarchar"
    | "nchar"
    | "uuid"
    | "json"
    | "jsonb" => "String"
    "real"
    | "double"
    | "float"
    | "float4"
    | "float8"
    | "numeric"
    | "decimal"
    | "money" => "Double"
    "blob" | "bytea" | "binary" | "varbinary" => "Bytes"
    "boolean" | "bool" => "Bool"
    _ => "String"
  }
}

///|
/// Uppercase a leading ASCII letter (MoonBit `String` has no `to_upper`, and only
/// the first letter of each `snake` word needs it for `PascalCase`).
fn upper_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let c = s[0].to_int()
  if c >= 0x61 && c <= 0x7A {
    match (c - 0x20).to_char() {
      Some(ch) => ch.to_string() + s[1:].to_owned()
      None => s
    }
  } else {
    s
  }
}

///|
/// Turn a `snake_case` table name into the `PascalCase` struct name its model maps
/// to (`blog_posts` → `BlogPosts`). Underscores split words; other characters carry
/// through.
fn to_pascal(s : String) -> String {
  let mut out = ""
  let mut word = ""
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == '_' {
      out = out + upper_first(word)
      word = ""
    } else {
      word = word + s[i:i + 1].to_owned()
    }
  }
  out + upper_first(word)
}

///|
/// Whether `c` ends a DDL token (whitespace or one of the structural delimiters).
fn is_ddl_delim(c : UInt16) -> Bool {
  is_ws(c) || c == '(' || c == ')' || c == ','
}

///|
/// Tokenise a SQL DDL source into words and the structural tokens `(` `)` `,`.
/// Line (`--`) and block (`/* */`) comments are dropped; double-quoted, backtick-
/// and bracket-quoted identifiers become a single bare-name token; a single-quoted
/// string literal is kept verbatim (quotes included) so a `DEFAULT 'x'` survives.
fn ddl_tokens(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s[i]
    if is_ws(c) {
      i = i + 1
    } else if c == '-' && i + 1 < n && s[i + 1] == '-' {
      while i < n && s[i] != '\n' {
        i = i + 1
      }
    } else if c == '/' && i + 1 < n && s[i + 1] == '*' {
      i = i + 2
      while i + 1 < n && !(s[i] == '*' && s[i + 1] == '/') {
        i = i + 1
      }
      i = i + 2
    } else if c == '(' || c == ')' || c == ',' {
      out.push(s[i:i + 1].to_owned())
      i = i + 1
    } else if c == '"' || c == '`' {
      let start = i + 1
      let mut j = start
      while j < n && s[j] != c {
        j = j + 1
      }
      out.push(s[start:j].to_owned())
      i = j + 1
    } else if c == '[' {
      let start = i + 1
      let mut j = start
      while j < n && s[j] != ']' {
        j = j + 1
      }
      out.push(s[start:j].to_owned())
      i = j + 1
    } else if c == '\'' {
      let start = i
      let mut j = i + 1
      while j < n && s[j] != '\'' {
        j = j + 1
      }
      out.push(s[start:j + 1].to_owned())
      i = j + 1
    } else {
      let start = i
      while i < n && !is_ddl_delim(s[i]) {
        i = i + 1
      }
      out.push(s[start:i].to_owned())
    }
  }
  out
}

///|
/// Split a `CREATE TABLE` body (the tokens between the outer parentheses) into its
/// top-level comma-separated definitions, tracking parenthesis depth so a type size
/// (`NUMERIC(10, 2)`) or a `PRIMARY KEY (a, b)` list is not split on its inner comma.
fn split_defs(body : Array[String]) -> Array[Array[String]] {
  let defs : Array[Array[String]] = []
  let mut cur : Array[String] = []
  let mut depth = 0
  for tok in body {
    if tok == "(" {
      depth = depth + 1
      cur.push(tok)
    } else if tok == ")" {
      depth = depth - 1
      cur.push(tok)
    } else if tok == "," && depth == 0 {
      defs.push(cur)
      cur = []
    } else {
      cur.push(tok)
    }
  }
  if cur.length() > 0 {
    defs.push(cur)
  }
  defs
}

///|
/// Parse one column definition (`name TYPE [flags…]`): map the type, and read the
/// `PRIMARY KEY`, `NOT NULL` and `DEFAULT` flags. A trailing type size (`VARCHAR
/// (255)`) is skipped. `PRIMARY KEY` implies `NOT NULL`.
fn parse_column_def(seg : Array[String]) -> DdlColumn {
  let name = seg[0]
  let sql_type = if seg.length() >= 2 { seg[1].to_lower() } else { "text" }
  let mb = map_sql_type(sql_type)
  let mut pk = false
  let mut nullable = true
  let mut default_ : String? = None
  let mut k = 2
  if k < seg.length() && seg[k] == "(" {
    while k < seg.length() && seg[k] != ")" {
      k = k + 1
    }
    if k < seg.length() {
      k = k + 1
    }
  }
  while k < seg.length() {
    let w = seg[k].to_lower()
    if w == "primary" && k + 1 < seg.length() && seg[k + 1].to_lower() == "key" {
      pk = true
      nullable = false
      k = k + 2
    } else if w == "not" &&
      k + 1 < seg.length() &&
      seg[k + 1].to_lower() == "null" {
      nullable = false
      k = k + 2
    } else if w == "default" && k + 1 < seg.length() {
      default_ = Some(seg[k + 1])
      k = k + 2
    } else {
      k = k + 1
    }
  }
  { name, type_: mb, primary_key: pk, nullable, default_, }
}

///|
/// Parse a `CREATE TABLE`'s body definitions into columns. A `PRIMARY KEY (col, …)`
/// table constraint flips the referenced columns' `primary_key`; other table
/// constraints (`FOREIGN KEY`, `UNIQUE`, `CONSTRAINT`, `CHECK`, a bare `KEY`) are
/// skipped — they do not add columns.
fn parse_table_body(name : String, body : Array[String]) -> DdlTable {
  let columns : Array[DdlColumn] = []
  let pk_names : Array[String] = []
  for seg in split_defs(body) {
    if seg.length() == 0 {
      continue
    }
    let head = seg[0].to_lower()
    if head == "primary" && seg.length() >= 2 && seg[1].to_lower() == "key" {
      for k = 2; k < seg.length(); k = k + 1 {
        let tk = seg[k]
        if tk != "(" && tk != ")" {
          pk_names.push(tk)
        }
      }
    } else if head == "foreign" ||
      head == "unique" ||
      head == "constraint" ||
      head == "check" ||
      head == "key" {
      continue
    } else {
      columns.push(parse_column_def(seg))
    }
  }
  for pkname in pk_names {
    for c in columns {
      if c.name == pkname {
        c.primary_key = true
      }
    }
  }
  { name, columns, }
}

///|
/// Parse a SQL DDL script into its `CREATE TABLE` definitions. Recognises `CREATE
/// TABLE [IF NOT EXISTS] name ( … )` (quoted or bare name), skipping any other
/// statement. Column types, primary keys (column- or table-level), `NOT NULL` and
/// `DEFAULT` clauses are captured; everything needed to emit a moonorm model.
pub fn parse_ddl(source : String) -> Array[DdlTable] {
  let toks = ddl_tokens(source)
  let tables : Array[DdlTable] = []
  let n = toks.length()
  let mut i = 0
  while i < n {
    if toks[i].to_lower() == "create" &&
      i + 1 < n &&
      toks[i + 1].to_lower() == "table" {
      i = i + 2
      while i < n &&
            (
              toks[i].to_lower() == "if" ||
              toks[i].to_lower() == "not" ||
              toks[i].to_lower() == "exists"
            ) {
        i = i + 1
      }
      if i >= n {
        break
      }
      let tname = toks[i]
      i = i + 1
      if i < n && toks[i] == "(" {
        i = i + 1
        let body : Array[String] = []
        let mut depth = 1
        while i < n && depth > 0 {
          let t = toks[i]
          if t == "(" {
            depth = depth + 1
            body.push(t)
          } else if t == ")" {
            depth = depth - 1
            if depth > 0 {
              body.push(t)
            }
          } else {
            body.push(t)
          }
          i = i + 1
        }
        tables.push(parse_table_body(tname, body))
      }
    } else {
      i = i + 1
    }
  }
  tables
}

///|
/// The single-column primary key of a table, or `None` when the table has no
/// primary key or a composite one (the by-id CRUD helpers key on a single column).
fn single_pk(t : DdlTable) -> DdlColumn? {
  let pks : Array[DdlColumn] = []
  for c in t.columns {
    if c.primary_key {
      pks.push(c)
    }
  }
  if pks.length() == 1 {
    Some(pks[0])
  } else {
    None
  }
}

///|
/// Emit the `struct` for a parsed table.
fn emit_ddl_struct(t : DdlTable, struct_name : String) -> String {
  let mut out = "///|\n/// `" +
    struct_name +
    "` model (generated from the `" +
    t.name +
    "` table).\npub(all) struct " +
    struct_name +
    " {\n"
  for c in t.columns {
    out = out + "  " + c.name + " : " + c.type_ + "\n"
  }
  out + "}\n\n"
}

///|
/// Emit the `@moonorm.Model[T]` value and the `@moonorm.Table` descriptor for a
/// parsed table. `vp` is the MoonBit value-name prefix; `sql` is the literal SQL
/// table name bound into the model.
fn emit_ddl_model(
  t : DdlTable,
  struct_name : String,
  vp : String,
  sql : String,
) -> String {
  let col_lines : Array[String] = []
  for c in t.columns {
    let cls = match storage_class(c.type_) {
      Some(x) => x
      None => "TextType"
    }
    let flags = if c.primary_key {
      ", primary_key=true"
    } else if !c.nullable {
      ", nullable=false"
    } else {
      ""
    }
    col_lines.push(
      "    @moonorm.column(" +
      quote(c.name) +
      ", @moonorm." +
      cls +
      flags +
      "),",
    )
  }
  let from_fields : Array[String] = []
  for i = 0; i < t.columns.length(); i = i + 1 {
    let c = t.columns[i]
    from_fields.push("    " + c.name + ": " + row_read(c.type_, i) + ",")
  }
  let to_pairs : Array[String] = []
  for c in t.columns {
    to_pairs.push(
      "    (" + quote(c.name) + ", " + value_ctor(c.type_, "r." + c.name) + "),",
    )
  }
  "///|\n/// Declarative model for `" +
  sql +
  "`: declared columns, a `@moondb.Row` decoder, and the column projection an\n/// INSERT binds.\npub let " +
  vp +
  "_model : @moonorm.Model[" +
  struct_name +
  "] = @moonorm.Model::new(\n  " +
  quote(sql) +
  ",\n  [\n" +
  join_lines(col_lines) +
  "\n  ],\n  row => {\n" +
  join_lines(from_fields) +
  "\n  },\n  r => [\n" +
  join_lines(to_pairs) +
  "\n  ],\n)\n\n" +
  "///|\n/// Table metadata for `" +
  sql +
  "` (name + column list).\npub let " +
  vp +
  "_table : @moonorm.Table = " +
  vp +
  "_model.table_descriptor()\n\n"
}

///|
/// Emit the `<vp>_up` / `<vp>_down` migration pair: create the table idempotently
/// through the model, drop it by name.
fn emit_ddl_migration(vp : String, sql : String) -> String {
  "///|\n/// Migration up: create the `" +
  sql +
  "` table (idempotent).\npub fn " +
  vp +
  "_up(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {\n  sess.create_table(" +
  vp +
  "_model, if_not_exists=true)\n}\n\n" +
  "///|\n/// Migration down: drop the `" +
  sql +
  "` table.\npub fn " +
  vp +
  "_down(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {\n  sess.execute(" +
  quote("DROP TABLE IF EXISTS " + sql) +
  ", [])\n}\n\n"
}

///|
/// Emit the typed CRUD helpers for a table. `insert` and `all` are always emitted;
/// `find_by_id`, `update` and `delete_by_id` need a single-column primary key (and
/// `update` also needs at least one non-key column to SET). Every statement is
/// parameterised — the id and every bound column travel as `?` placeholders.
fn emit_ddl_crud(
  t : DdlTable,
  struct_name : String,
  vp : String,
  sql : String,
) -> String {
  let mut out = "///|\n/// Insert a `" +
    struct_name +
    "` record.\npub fn " +
    vp +
    "_insert(sess : @moonorm.Session, record : " +
    struct_name +
    ") -> @moondb.ExecResult raise @moondb.DbError {\n  sess.insert_record(" +
    vp +
    "_model, record)\n}\n\n"
  out = out +
    "///|\n/// Every `" +
    sql +
    "` row.\npub fn " +
    vp +
    "_all(sess : @moonorm.Session) -> Array[" +
    struct_name +
    "] raise @moondb.DbError {\n  sess.all(" +
    vp +
    "_model)\n}\n\n"
  match single_pk(t) {
    None => out
    Some(pk) => {
      let id_ctor = value_ctor(pk.type_, "id")
      out = out +
        "///|\n/// Fetch the `" +
        sql +
        "` row whose `" +
        pk.name +
        "` is `id`, or `None`.\npub fn " +
        vp +
        "_find_by_id(sess : @moonorm.Session, id : " +
        pk.type_ +
        ") -> " +
        struct_name +
        "? raise @moondb.DbError {\n  let rows = sess.fetch_as(" +
        vp +
        "_model, " +
        vp +
        "_model.select().where_(" +
        quote(pk.name) +
        ", \"=\", " +
        id_ctor +
        ").limit(1))\n  if rows.length() == 0 {\n    None\n  } else {\n    Some(rows[0])\n  }\n}\n\n"
      out = out +
        "///|\n/// Delete the `" +
        sql +
        "` row whose `" +
        pk.name +
        "` is `id`.\npub fn " +
        vp +
        "_delete_by_id(sess : @moonorm.Session, id : " +
        pk.type_ +
        ") -> @moondb.ExecResult raise @moondb.DbError {\n  sess.remove(@moonorm.delete(" +
        quote(sql) +
        ").where_(" +
        quote(pk.name) +
        ", \"=\", " +
        id_ctor +
        "))\n}\n\n"
      let sets : Array[String] = []
      for c in t.columns {
        if !c.primary_key {
          sets.push(
            ".set(" +
            quote(c.name) +
            ", " +
            value_ctor(c.type_, "record." + c.name) +
            ")",
          )
        }
      }
      if sets.length() > 0 {
        let mut chain = "@moonorm.update(" + quote(sql) + ")"
        for s in sets {
          chain = chain + s
        }
        chain = chain +
          ".where_(" +
          quote(pk.name) +
          ", \"=\", " +
          value_ctor(pk.type_, "record." + pk.name) +
          ")"
        out = out +
          "///|\n/// Update the `" +
          sql +
          "` row matching `record`'s primary key.\npub fn " +
          vp +
          "_update(sess : @moonorm.Session, record : " +
          struct_name +
          ") -> @moondb.ExecResult raise @moondb.DbError {\n  sess.modify(" +
          chain +
          ")\n}\n\n"
      }
      out
    }
  }
}

///|
/// Generate a moonorm data-access layer from parsed DDL: for every table, the record
/// `struct`, its `@moonorm.Model` (columns + `from_row` + `to_columns`), a
/// `@moonorm.Table` descriptor, an up/down migration pair, and typed CRUD
/// (`insert`/`all`, plus `find_by_id`/`update`/`delete_by_id` when the table has a
/// single-column primary key). The output compiles against `moonbitstack/moonorm` +
/// `moonbitstack/moondb`; a consuming package imports both. This is the `.sql`-schema
/// counterpart of goctl's `model mysql ddl`.
pub fn generate_crud(tables : Array[DdlTable]) -> String {
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n"
  for t in tables {
    let struct_name = to_pascal(t.name)
    let vp = to_snake(t.name)
    let sql = t.name
    out = out + emit_ddl_struct(t, struct_name)
    out = out + emit_ddl_model(t, struct_name, vp, sql)
    out = out + emit_ddl_migration(vp, sql)
    out = out + emit_ddl_crud(t, struct_name, vp, sql)
  }
  out
}

///|
/// Parse a SQL DDL script and generate its moonorm data-access layer in one step.
pub fn generate_crud_from_ddl(source : String) -> String {
  generate_crud(parse_ddl(source))
}
