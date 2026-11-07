// The `model` sub-command's SQL front end: parse a `CREATE TABLE` DDL and emit a
// moonorm data-access layer for it. goctl reads a live MySQL/Postgres schema (or a
// `.sql` file) and generates a model with typed CRUD; this is the `.sql`-file half
// of that, transliterated. The generated code compiles against moonbitstack/moonorm +
// moonbitstack/moondb, and its statements are all parameterised, so a generated CRUD call
// is injection-safe by construction.

///|
/// One parsed column of a `CREATE TABLE` statement: the SQL column `name`, the
/// MoonBit `type_` its SQL type maps to (`Int`/`Int64`/`String`/`Double`/`Bool`/
/// `Bytes`), whether it is a primary key, whether it accepts NULL, its literal
/// `DEFAULT` clause if any (kept as source text — it is emitted into DDL comments,
/// never bound), and whether the column itself carries `UNIQUE`.
pub(all) struct DdlColumn {
  name : String
  type_ : String
  mut primary_key : Bool
  nullable : Bool
  default_ : String?
  unique : Bool
}

///|
/// An index the DDL asked for, from `CREATE INDEX`, a `UNIQUE`/`KEY` table
/// constraint, or a column's own `UNIQUE`: the `name` the DDL gave it (empty when
/// it left the naming to the database), the `columns` it covers in order, and
/// whether it is `unique`.
pub(all) struct DdlIndex {
  name : String
  columns : Array[String]
  unique : Bool
}

///|
/// A foreign key: the referencing `columns` on this table, the `ref_table` and
/// `ref_columns` they point at, and the referential actions the DDL asked for
/// (`""` when it named none).
pub(all) struct DdlForeignKey {
  columns : Array[String]
  ref_table : String
  ref_columns : Array[String]
  on_delete : String
  on_update : String
}

///|
/// A parsed `CREATE TABLE`: the SQL table `name`, its ordered `columns`, the
/// `indexes` declared for it, and the `foreign_keys` its columns take part in.
pub(all) struct DdlTable {
  name : String
  columns : Array[DdlColumn]
  indexes : Array[DdlIndex]
  foreign_keys : Array[DdlForeignKey]
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
    | "serial" => "Int32"
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
/// Whether `c` ends a DDL token (whitespace or one of the structural delimiters).
fn is_ddl_delim(c : UInt16) -> Bool {
  @text.is_ws(c) || c == '(' || c == ')' || c == ','
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
    if @text.is_ws(c) {
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
/// Whether `w` is a keyword that ends a foreign key's referential action list.
fn ends_actions(w : String) -> Bool {
  w == "on" ||
  w == "not" ||
  w == "deferrable" ||
  w == "initially" ||
  w == "match"
}

///|
/// The items inside the first `( … )` at or after `from`, and the index just past
/// its closing paren. Nesting is tracked, so an index on an expression
/// (`(lower(name))`) yields the outer words only — a column list is what the
/// caller can annotate.
fn ddl_paren_items(seg : Array[String], from : Int32) -> (Array[String], Int32) {
  let out : Array[String] = []
  let n = seg.length()
  let mut i = from
  while i < n && seg[i] != "(" {
    i = i + 1
  }
  if i >= n {
    return (out, n)
  }
  let mut depth = 0
  while i < n {
    let t = seg[i]
    if t == "(" {
      depth = depth + 1
    } else if t == ")" {
      depth = depth - 1
      if depth == 0 {
        return (out, i + 1)
      }
    } else if depth == 1 && t != "," {
      out.push(t)
    }
    i = i + 1
  }
  (out, n)
}

///|
/// The referential actions from `from` on, as `(on_delete, on_update, next)` —
/// spelt the way the DDL spelt them, since they are emitted into DDL verbatim.
/// `next` is always the end of the definition.
fn ddl_actions(seg : Array[String], from : Int32) -> (String, String, Int32) {
  let n = seg.length()
  let mut i = from
  let mut on_delete = ""
  let mut on_update = ""
  while i < n {
    if seg[i].to_lower() == "on" && i + 1 < n {
      let what = seg[i + 1].to_lower()
      let mut j = i + 2
      let mut action = ""
      while j < n && !ends_actions(seg[j].to_lower()) {
        action = if action == "" { seg[j] } else { action + " " + seg[j] }
        j = j + 1
      }
      if what == "delete" {
        on_delete = action
      } else if what == "update" {
        on_update = action
      }
      i = j
    } else {
      i = i + 1
    }
  }
  (on_delete, on_update, n)
}

///|
/// Parse one column definition (`name TYPE [flags…]`): map the type, and read the
/// `PRIMARY KEY`, `NOT NULL`, `DEFAULT`, `UNIQUE` and `REFERENCES` flags. A trailing
/// type size (`VARCHAR (255)`) is skipped. `PRIMARY KEY` implies `NOT NULL`. The
/// second half of the pair is the foreign key a `REFERENCES` clause declared.
fn parse_column_def(seg : Array[String]) -> (DdlColumn, DdlForeignKey?) {
  let name = seg[0]
  let sql_type = if seg.length() >= 2 { seg[1].to_lower() } else { "text" }
  let mb = map_sql_type(sql_type)
  let mut pk = false
  let mut nullable = true
  let mut unique = false
  let mut default_ : String? = None
  let mut ref_table = ""
  let mut ref_cols : Array[String] = []
  let mut on_delete = ""
  let mut on_update = ""
  let mut k = 2
  if k < seg.length() && seg[k] == "(" {
    let (_, after) = ddl_paren_items(seg, k)
    k = after
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
    } else if w == "unique" {
      unique = true
      k = k + 1
    } else if w == "references" && k + 1 < seg.length() {
      ref_table = seg[k + 1]
      k = k + 2
      if k < seg.length() && seg[k] == "(" {
        let (cols, after) = ddl_paren_items(seg, k)
        ref_cols = cols
        k = after
      }
      let (del, upd, next) = ddl_actions(seg, k)
      on_delete = del
      on_update = upd
      k = next
    } else {
      k = k + 1
    }
  }
  let fk = if ref_table == "" {
    None
  } else {
    Some({
      columns: [name],
      ref_table,
      ref_columns: ref_cols,
      on_delete,
      on_update,
    })
  }
  ({ name, type_: mb, primary_key: pk, nullable, default_, unique, }, fk)
}

///|
/// A `constraint <name> …` definition without its leading `constraint <name>`.
fn strip_constraint(seg : Array[String]) -> Array[String] {
  if seg.length() >= 2 && seg[0].to_lower() == "constraint" {
    seg[2:].to_owned()
  } else {
    seg
  }
}

///|
/// A `FOREIGN KEY ( … ) REFERENCES …` definition (with or without a leading
/// `constraint <name>`), or `None` when the definition is not one.
fn parse_fk_def(seg : Array[String]) -> DdlForeignKey? {
  let n = seg.length()
  let mut i = 0
  if i < n && seg[i].to_lower() == "constraint" {
    i = i + 2
  }
  if i >= n || seg[i].to_lower() != "foreign" {
    return None
  }
  i = i + 1
  if i < n && seg[i].to_lower() == "key" {
    i = i + 1
  }
  let (cols, after) = ddl_paren_items(seg, i)
  i = after
  if cols.length() == 0 || i >= n || seg[i].to_lower() != "references" {
    return None
  }
  i = i + 1
  if i >= n {
    return None
  }
  let ref_table = seg[i]
  i = i + 1
  let mut ref_cols : Array[String] = []
  if i < n && seg[i] == "(" {
    let (cols2, after2) = ddl_paren_items(seg, i)
    ref_cols = cols2
    i = after2
  }
  let (on_delete, on_update, _) = ddl_actions(seg, i)
  Some({
    columns: cols,
    ref_table,
    ref_columns: ref_cols,
    on_delete,
    on_update,
  })
}

///|
/// A `UNIQUE`/`KEY`/`INDEX` definition (with or without a leading
/// `constraint <name>`), or `None` when the definition is not one.
fn parse_index_def(seg : Array[String]) -> DdlIndex? {
  let n = seg.length()
  let mut i = 0
  let mut unique = false
  if i < n && seg[i].to_lower() == "unique" {
    unique = true
    i = i + 1
  }
  if i >= n {
    return None
  }
  let word = seg[i].to_lower()
  if word == "key" || word == "index" {
    i = i + 1
  } else if !unique {
    return None
  }
  let mut name = ""
  if i < n && seg[i] != "(" {
    name = seg[i]
    i = i + 1
  }
  let (cols, _) = ddl_paren_items(seg, i)
  if cols.length() == 0 {
    return None
  }
  Some({ name, columns: cols, unique, })
}

///|
/// Parse a `CREATE TABLE`'s body definitions into columns, indexes and foreign
/// keys. A `PRIMARY KEY (col, …)` table constraint flips the referenced columns'
/// `primary_key`; a `UNIQUE`/`KEY`/`INDEX` constraint becomes a `DdlIndex`, a
/// `FOREIGN KEY … REFERENCES …` a `DdlForeignKey`, and a `CHECK` is read past — it
/// constrains values rather than naming a column.
fn parse_table_body(name : String, body : Array[String]) -> DdlTable {
  let columns : Array[DdlColumn] = []
  let indexes : Array[DdlIndex] = []
  let fks : Array[DdlForeignKey] = []
  let pk_names : Array[String] = []
  for seg in split_defs(body) {
    if seg.length() == 0 {
      continue
    }
    let head = seg[0].to_lower()
    if head == "primary" && seg.length() >= 2 && seg[1].to_lower() == "key" {
      let (cols, _) = ddl_paren_items(seg, 2)
      for c in cols {
        pk_names.push(c)
      }
    } else if head == "foreign" ||
      head == "constraint" ||
      head == "unique" ||
      head == "check" ||
      head == "key" ||
      head == "index" {
      let bare = strip_constraint(seg)
      match parse_fk_def(bare) {
        Some(fk) => fks.push(fk)
        None =>
          match parse_index_def(bare) {
            Some(ix) => indexes.push(ix)
            None => ()
          }
      }
    } else {
      let (col, fk) = parse_column_def(seg)
      columns.push(col)
      match fk {
        Some(f) => fks.push(f)
        None => ()
      }
    }
  }
  for pkname in pk_names {
    for c in columns {
      if c.name == pkname {
        c.primary_key = true
      }
    }
  }
  { name, columns, indexes, foreign_keys: fks, }
}

///|
/// Parse a SQL DDL script into its `CREATE TABLE` definitions. Recognises `CREATE
/// TABLE [IF NOT EXISTS] name ( … )` (quoted or bare name) and `CREATE [UNIQUE]
/// INDEX [IF NOT EXISTS] name ON table ( … )`, skipping any other statement. Column
/// types, primary keys (column- or table-level), `NOT NULL`, `UNIQUE`, `DEFAULT`
/// and `REFERENCES` clauses are captured, plus the table's own index and foreign-key
/// constraints — everything needed to emit a moonorm model and its relations.
pub fn parse_ddl(source : String) -> Array[DdlTable] {
  let toks = ddl_tokens(source)
  let tables : Array[DdlTable] = []
  let loose : Array[(String, DdlIndex)] = []
  let n = toks.length()
  let mut i = 0
  while i < n {
    if toks[i].to_lower() != "create" {
      i = i + 1
      continue
    }
    let mut j = i + 1
    let mut unique = false
    if j < n && toks[j].to_lower() == "unique" {
      unique = true
      j = j + 1
    }
    if j >= n {
      break
    }
    let what = toks[j].to_lower()
    if what == "table" {
      j = j + 1
      while j < n &&
            (
              toks[j].to_lower() == "if" ||
              toks[j].to_lower() == "not" ||
              toks[j].to_lower() == "exists"
            ) {
        j = j + 1
      }
      if j >= n {
        break
      }
      let tname = toks[j]
      j = j + 1
      if j < n && toks[j] == "(" {
        j = j + 1
        let body : Array[String] = []
        let mut depth = 1
        while j < n && depth > 0 {
          let t = toks[j]
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
          j = j + 1
        }
        tables.push(parse_table_body(tname, body))
        i = j
      } else {
        i = j
      }
    } else if what == "index" {
      j = j + 1
      while j < n &&
            (
              toks[j].to_lower() == "if" ||
              toks[j].to_lower() == "not" ||
              toks[j].to_lower() == "exists"
            ) {
        j = j + 1
      }
      if j >= n {
        break
      }
      let iname = toks[j]
      j = j + 1
      if j < n && toks[j].to_lower() == "on" {
        j = j + 1
        if j >= n {
          break
        }
        let tname = toks[j]
        j = j + 1
        let (cols, after) = ddl_paren_items(toks, j)
        if cols.length() > 0 {
          loose.push((tname, { name: iname, columns: cols, unique, }))
        }
        i = after
      } else {
        i = j
      }
    } else {
      i = j
    }
  }
  for entry in loose {
    let target = entry.0.to_lower()
    for t in tables {
      if t.name.to_lower() == target {
        t.indexes.push(entry.1)
      }
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
/// The foreign key a column takes part in, when the DDL declared one for it.
pub fn ddl_fk_of(t : DdlTable, column : String) -> DdlForeignKey? {
  for fk in t.foreign_keys {
    for c in fk.columns {
      if c == column {
        return Some(fk)
      }
    }
  }
  None
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
    let flags = StringBuilder()
    if c.primary_key {
      flags.write_string(", primary_key=true")
    } else if !c.nullable {
      flags.write_string(", nullable=false")
    }
    if c.unique {
      flags.write_string(", unique=true")
    }
    match ddl_fk_of(t, c.name) {
      Some(fk) => {
        let target = match fk.ref_columns {
          [] => ""
          [one, ..] => one
        }
        flags.write_string(
          ", references=(" +
          @text.quote(fk.ref_table) +
          ", " +
          @text.quote(target) +
          ")",
        )
        if fk.on_delete != "" {
          flags.write_string(", on_delete=" + @text.quote(fk.on_delete))
        }
        if fk.on_update != "" {
          flags.write_string(", on_update=" + @text.quote(fk.on_update))
        }
      }
      None => ()
    }
    col_lines.push(
      "    @moonorm.column(" +
      @text.quote(c.name) +
      ", " +
      cls +
      flags.to_string() +
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
      "    (" +
      @text.quote(c.name) +
      ", " +
      value_ctor(c.type_, "r." + c.name) +
      "),",
    )
  }
  let mut index_arg = ""
  if t.indexes.length() > 0 {
    let lines : Array[String] = []
    for ix in t.indexes {
      let parts : Array[String] = [
        "[" + ix.columns.map(@text.quote).join(", ") + "]",
      ]
      if ix.name != "" {
        parts.push("name=" + @text.quote(ix.name))
      }
      if ix.unique {
        parts.push("unique=true")
      }
      lines.push("    @moonorm.index(" + parts.join(", ") + "),")
    }
    index_arg = "\n  indexes=[\n" + @text.join_lines(lines) + "\n  ],"
  }
  "///|\n/// Declarative model for `" +
  sql +
  "`: declared columns, a `@moondb.Row` decoder, and the column projection an\n/// INSERT binds.\npub let " +
  vp +
  "_model : @moonorm.Model[" +
  struct_name +
  "] = @moonorm.Model::new(\n  " +
  @text.quote(sql) +
  ",\n  [\n" +
  @text.join_lines(col_lines) +
  "\n  ],\n  row => {\n" +
  @text.join_lines(from_fields) +
  "\n  },\n  r => [\n" +
  @text.join_lines(to_pairs) +
  "\n  ]," +
  index_arg +
  "\n)\n\n" +
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
fn emit_ddl_migration(vp : String, sql : String, model_expr : String) -> String {
  "///|\n/// Migration up: create the `" +
  sql +
  "` table (idempotent).\npub fn " +
  vp +
  "_up(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {\n  sess.create_table(" +
  model_expr +
  ", if_not_exists=true)\n}\n\n" +
  "///|\n/// Migration down: drop the `" +
  sql +
  "` table.\npub fn " +
  vp +
  "_down(sess : @moonorm.Session) -> @moondb.ExecResult raise @moondb.DbError {\n  sess.execute(" +
  @text.quote("DROP TABLE IF EXISTS " + sql) +
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
  model_expr : String,
  nullable_aware~ : Bool = false,
) -> String {
  let bind = (c : DdlColumn, expr : String) => {
    if nullable_aware && c.nullable && !c.primary_key {
      // The annotated form declares a nullable column optional, so `None` has to
      // travel as SQL `NULL` rather than as a value of the column's type.
      "match " +
      expr +
      " {\n      Some(v) => " +
      value_ctor(c.type_, "v") +
      ",\n      None => @moondb.Null,\n    }"
    } else {
      value_ctor(c.type_, expr)
    }
  }
  let mut out = "///|\n/// Insert a `" +
    struct_name +
    "` record.\npub fn " +
    vp +
    "_insert(sess : @moonorm.Session, record : " +
    struct_name +
    ") -> @moondb.ExecResult raise @moondb.DbError {\n  sess.insert_record(" +
    model_expr +
    ", record)\n}\n\n"
  out = out +
    "///|\n/// Every `" +
    sql +
    "` row.\npub fn " +
    vp +
    "_all(sess : @moonorm.Session) -> Array[" +
    struct_name +
    "] raise @moondb.DbError {\n  sess.all(" +
    model_expr +
    ")\n}\n\n"
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
        model_expr +
        ", " +
        model_expr +
        ".select().where_(" +
        @text.quote(pk.name) +
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
        @text.quote(sql) +
        ").where_(" +
        @text.quote(pk.name) +
        ", \"=\", " +
        id_ctor +
        "))\n}\n\n"
      let sets : Array[String] = []
      for c in t.columns {
        if !c.primary_key {
          sets.push(
            ".set(" +
            @text.quote(c.name) +
            ", " +
            bind(c, "record." + c.name) +
            ")",
          )
        }
      }
      if sets.length() > 0 {
        let mut chain = "@moonorm.update(" + @text.quote(sql) + ")"
        for s in sets {
          chain = chain + s
        }
        chain = chain +
          ".where_(" +
          @text.quote(pk.name) +
          ", \"=\", " +
          bind(pk, "record." + pk.name) +
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
    let struct_name = @text.to_pascal(t.name)
    let vp = @text.to_snake(t.name)
    let sql = t.name
    out = out + emit_ddl_struct(t, struct_name)
    out = out + emit_ddl_model(t, struct_name, vp, sql)
    let model_expr = vp + "_model"
    out = out + emit_ddl_migration(vp, sql, model_expr)
    out = out + emit_ddl_crud(t, struct_name, vp, sql, model_expr)
  }
  out
}

///|
/// The typed CRUD helpers for one table, against the model `model_expr` names.
/// `nullable_aware` binds an optional field of a nullable column as SQL `NULL`,
/// which is what the annotated form's optional types need.
pub fn crud_for(
  t : DdlTable,
  model_expr : String,
  nullable_aware~ : Bool = false,
) -> String {
  emit_ddl_crud(
    t,
    @text.to_pascal(t.name),
    @text.to_snake(t.name),
    t.name,
    model_expr,
    nullable_aware~,
  )
}

///|
/// The `<table>_up` / `<table>_down` migration pair for one table, against the
/// model `model_expr` names.
pub fn migration_for(t : DdlTable, model_expr : String) -> String {
  emit_ddl_migration(@text.to_snake(t.name), t.name, model_expr)
}

///|
/// Parse a SQL DDL script and generate its moonorm data-access layer in one step.
pub fn generate_crud_from_ddl(source : String) -> String {
  generate_crud(parse_ddl(source))
}
