// `mctl migrate` (← goctl's `migrate`): the SQL a spec's types imply.
//
// A `.api` spec describes the shapes a service carries, and those shapes are, more
// often than not, also the tables the service stores. `generate_migrations` reads
// every `type` block as a table: one column per field, the field's name as the
// column, its type as a SQL type, and the `id` field as the primary key.
//
// It is a starting point on purpose — a spec knows the shape of a value, not
// whether it is unique, indexed, or a foreign key. The generated file says so at
// the top, so nobody mistakes it for a schema a database already agrees with.

///|
/// The SQL type a MoonBit field type is stored as, in MySQL's spelling. A structure
/// a database has no column type for — a list, a map, another `type` block — is
/// `JSON`, which every engine mctl targets accepts.
fn sql_type(t : String) -> String {
  let s = @text.trim(t)
  if @text.ends_with(s, "?") {
    return sql_type(s[0:s.length() - 1].to_owned())
  }
  if @text.starts_with(s, "Array[") || @text.starts_with(s, "Map[") {
    return "JSON"
  }
  match s {
    "String" => "VARCHAR(191)"
    "Bytes" => "BLOB"
    "Bool" => "TINYINT(1)"
    "Int" | "Int32" => "INT"
    "Int64" => "BIGINT"
    "UInt" | "UInt32" => "INT UNSIGNED"
    "UInt64" => "BIGINT UNSIGNED"
    "Byte" => "TINYINT"
    "Float" => "FLOAT"
    "Double" => "DOUBLE"
    "Json" => "JSON"
    _ => "JSON"
  }
}

///|
/// The table a type block becomes: its name in `snake_case`, pluralised the way a
/// table usually is. A name that already ends in `s` is left alone, so `Address`
/// does not become `addresss`.
fn table_name(type_name : String) -> String {
  let base = @text.to_snake(type_name)
  if @text.ends_with(base, "s") {
    base
  } else {
    base + "s"
  }
}

///|
/// Whether a field is the primary key: the one called `id`, which is the one every
/// other row is referred to by.
fn is_primary(f : @api.Field) -> Bool {
  f.mbt_name() == "id" || f.json_name() == "id"
}

///|
/// One `type` block as one `CREATE TABLE`, or `None` for a block with no field —
/// there is nothing to create, and an empty table is a mistake rather than a
/// schema.
fn create_table(t : @api.TypeDef, types : Array[@api.TypeDef]) -> String? {
  let fields = @api.flat_fields(t, types)
  if fields.length() == 0 {
    return None
  }
  let out : Array[String] = []
  let table = table_name(t.name)
  out.push("-- " + t.name)
  out.push("CREATE TABLE IF NOT EXISTS `" + table + "` (")
  let mut key = ""
  let lines : Array[String] = []
  for f in fields {
    let column = @text.to_snake(f.json_name())
    let mut line = "  `" +
      @text.to_snake(f.json_name()) +
      "` " +
      sql_type(f.type_)
    if is_primary(f) && sql_type(f.type_) != "JSON" {
      line = line + " NOT NULL"
      key = column
    } else if f.optional() {
      line = line + " NULL"
    } else {
      line = line + " NOT NULL"
    }
    lines.push(line)
  }
  if key != "" {
    lines.push("  PRIMARY KEY (`" + key + "`)")
  }
  for i = 0; i < lines.length(); i = i + 1 {
    out.push(lines[i] + (if i + 1 < lines.length() { "," } else { "" }))
  }
  out.push(");")
  out.push("")
  Some(@text.join_lines(out))
}

///|
/// The migration file for a spec: one `CREATE TABLE` per type. `service` names the
/// file and the header, so two specs migrated into one directory do not look alike.
pub fn generate_migrations(spec : @api.Spec) -> String {
  let out : Array[String] = []
  out.push(
    "-- mctl migrate: " +
    (if spec.service == "" { "schema" } else { spec.service }),
  )
  out.push("--")
  out.push(
    "-- One table per `type` block of the spec. A spec says what a value looks",
  )
  out.push(
    "-- like, not what the database should enforce: indexes, uniqueness and foreign",
  )
  out.push(
    "-- keys are yours to add. Types used only as requests or responses are tables",
  )
  out.push("-- here too — drop the ones that are not stored.")
  out.push("")
  let mut wrote = false
  for t in spec.types {
    match create_table(t, spec.types) {
      Some(sql) => {
        out.push(sql)
        wrote = true
      }
      None => ()
    }
  }
  if wrote == false {
    out.push(
      "-- the spec declares no type with a field, so there is nothing to create",
    )
  }
  @text.join_lines(out)
}

///|
/// The name a migration file takes: `greet` → `greet_migrate.sql`.
pub fn migrate_file_name(service : String) -> String {
  (if service == "" { "schema" } else { @text.to_snake(service) }) +
  "_migrate.sql"
}
