// The `model` tree: tables declared with `#orm` annotations, and the build rule
// that turns them into `T::model()`.
//
// The annotation is the declaration. `moonorm`'s own generator reads these structs
// and writes the `@moonorm.Model[T]` — columns, row decoder, insert projection —
// into `<file>.g.mbt` at build time, so what this generator emits is the table
// itself rather than a hand-built copy of it. Only the parts moonorm cannot know
// are written here: the migrations and, for a SQL schema, the CRUD helpers.

///|
/// The package the annotated models live in.
let orm_pkg = "internal/model"

///|
/// `ty` without the trailing `?` that makes it optional.
fn orm_base(ty : String) -> String {
  if @text.ends_with(ty, "?") {
    ty[0:ty.length() - 1].to_owned()
  } else {
    ty
  }
}

///|
/// The `#orm.column` a field needs beyond what its type already says: a primary
/// key, the SQL kind of a MoonBit type `moonorm` has no default column for,
/// `autoincrement` on an optional integer key, `unique`, and the foreign key the
/// column points at. `None` when the type says it all.
fn orm_annotation(
  ty : String,
  primary_key : Bool,
  default : String?,
  unique~ : Bool = false,
  references~ : String = "",
  on_delete~ : String = "",
  on_update~ : String = "",
) -> String? {
  let base = orm_base(ty)
  let args : Array[String] = []
  if primary_key {
    args.push("primary_key=true")
    // Only an optional key can be left for the database to assign.
    if @text.ends_with(ty, "?") && (base == "Int32" || base == "Int64") {
      args.push("autoincrement=true")
    }
  }
  if unique {
    args.push("unique=true")
  }
  match orm_kind(base) {
    Some(kind) => args.push("kind=" + @text.quote(kind))
    None => ()
  }
  match default {
    Some(text) => args.push("default=" + @text.quote(text))
    None => ()
  }
  if references != "" {
    args.push("references=" + @text.quote(references))
    if on_delete != "" {
      args.push("on_delete=" + @text.quote(on_delete))
    }
    if on_update != "" {
      args.push("on_update=" + @text.quote(on_update))
    }
  }
  if args.length() == 0 {
    None
  } else {
    Some("#orm.column(" + args.join(", ") + ")")
  }
}

///|
/// The `kind=` argument for a MoonBit type `moonorm` has no default column for.
/// `Int32` is 32 bits wide where `moonorm`'s `IntType` is the platform word, so it
/// has to say which column it wants; every other type in the `.api`/DDL vocabulary
/// maps on its own.
fn orm_kind(base : String) -> String? {
  match base {
    "Int32" => Some("int")
    _ => None
  }
}

///|
/// One annotated field: its column annotation, if it needs one, over the field
/// itself. A field whose type has no single-column storage — a slice, a map, a
/// nested `type` — takes `#orm.skip`, which keeps it out of the table and fills it
/// from `Default` when a row is read.
fn orm_field(
  field : String,
  ty : String,
  primary_key : Bool,
  default : String?,
  unique~ : Bool = false,
  references~ : String = "",
  on_delete~ : String = "",
  on_update~ : String = "",
) -> String {
  let note = match @model.storage_class(orm_base(ty)) {
    Some(_) =>
      match
        orm_annotation(
          ty,
          primary_key,
          default,
          unique~,
          references~,
          on_delete~,
          on_update~,
        ) {
        Some(annotation) => "  " + annotation + "\n"
        None => ""
      }
    None => "  #orm.skip\n"
  }
  note + "  " + field + " : " + ty + "\n"
}

///|
/// One field of an annotated struct: its MoonBit `name`, its `ty`, and what the
/// schema said about the column beyond that — `unique`, and the foreign key it
/// points at (`references` as `table.column`, with the two referential actions).
priv struct OrmField {
  name : String
  ty : String
  unique : Bool
  references : String
  on_delete : String
  on_update : String
}

///|
/// A field that carries nothing beyond its type.
fn orm_plain_field(name : String, ty : String) -> OrmField {
  { name, ty, unique: false, references: "", on_delete: "", on_update: "", }
}

///|
/// Whether any field of a struct takes `#orm.skip`, which is what makes
/// `#derive(Default)` necessary.
fn orm_skips(fields : Array[OrmField]) -> Bool {
  for f in fields {
    if @model.storage_class(orm_base(f.ty)) is None {
      return true
    }
  }
  false
}

///|
/// The annotated struct for one table. `table` is the SQL name, `name` the MoonBit
/// type, `fields` its fields in declaration order, `indexes` the `#orm.index`
/// annotations the schema asked for and `relations` the `#orm.has_many` /
/// `#orm.belongs_to` ones it implies.
fn orm_struct(
  name : String,
  table : String,
  doc : String,
  fields : Array[OrmField],
  key : String,
  defaults : Map[String, String],
  indexes~ : Array[String] = [],
  relations~ : Array[String] = [],
) -> String {
  let skips = orm_skips(fields)
  let mut out = "///|\n/// " + doc + "\n"
  if skips {
    out = out + "#derive(Default)\n"
  }
  out = out + "#orm.table(name=" + @text.quote(table) + ")\n"
  for ix in indexes {
    out = out + ix + "\n"
  }
  for rel in relations {
    out = out + rel + "\n"
  }
  out = out + "pub(all) struct " + name + " {\n"
  for f in fields {
    let default = defaults.get(f.name)
    out = out +
      orm_field(
        f.name,
        f.ty,
        f.name == key,
        default,
        unique=f.unique,
        references=f.references,
        on_delete=f.on_delete,
        on_update=f.on_update,
      )
  }
  out = out + "}\n"
  if skips {
    // The derive puts the impl in the type's own package, which promotes its
    // methods onto the type; saying so explicitly keeps that a choice.
    out = out +
      "\n///|\n/// `" +
      name +
      "` with every field at its default, which is what a `#orm.skip` field is\n/// filled from when a row is read.\npub extend " +
      name +
      " with Default::{default}\n"
  }
  out
}

///|
/// The `moon.pkg` of the model package: the library, the rule that regenerates the
/// model from the annotations, and the formatter exemption for what it writes.
fn orm_pkg_file(imports : Array[(String, String)]) -> String {
  let mut out = pkg_file(imports)
  out = out +
    "\ndev_build(rule: \"orm\", input: \"models.mbt\", output: \"models.g.mbt\")\n"
  out = out + "\nformatter(ignore: [ \"models.g.mbt\" ])\n"
  out
}

///|
/// The `moon.mod` of a model module: the two libraries and the rule that runs
/// `moonorm`'s generator over the annotated file.
fn orm_mod_file(module_ : String) -> String {
  mod_file(module_, ["moonbitstack/moonorm", "moonbitstack/moondb"]) +
  "\n" +
  rule_line("orm", generator_command("moonbitstack/moonorm", "orm"))
}

///|
/// The tree a model module is made of: the module file, the package with its build
/// rule, the annotated models, the migrations, and the CRUD helpers when there are
/// any. `crud` is `Once` — it is the half the author edits.
fn orm_tree(
  module_ : String,
  st : @style.Style,
  dir : String,
  models : String,
  migrate : String,
  crud : String,
) -> Array[TreeFile] {
  let imports : Array[(String, String)] = [("moonbitstack/moonorm", "")]
  if migrate != "" || crud != "" {
    imports.push(("moonbitstack/moondb", ""))
  }
  let out : Array[TreeFile] = [
    { path: at(dir, "moon.mod"), content: orm_mod_file(module_), regen: Once, },
    {
      path: at(dir, orm_pkg + "/moon.pkg"),
      content: orm_pkg_file(imports),
      regen: Once,
    },
    {
      path: at(dir, orm_pkg + "/" + st.format("models") + ".mbt"),
      content: models,
      regen: Always,
    },
  ]
  if migrate != "" {
    out.push({
      path: at(dir, orm_pkg + "/" + st.format("migrate") + ".mbt"),
      content: migrate,
      regen: Always,
    })
  }
  if crud != "" {
    out.push({
      path: at(dir, orm_pkg + "/" + st.format("crud") + ".mbt"),
      content: crud,
      regen: Once,
    })
  }
  out
}

///|
/// The annotated models and migrations for `spec`: every `type` block is a table,
/// its `id` field (when it has one) the primary key, and a field with no single
/// column — a slice, a map, a nested type — is skipped rather than stored.
pub fn generate_orm_tree(
  spec : @api.Spec,
  style? : @style.Style,
  dir~ : String = "",
) -> Array[TreeFile] {
  let st = style.unwrap_or(@style.Style::gozero())
  let mut models = "// Code generated by moonctl from the `.api` spec. DO NOT EDIT.\n//\n// Each struct is a table: `#orm.table` names it, and the `@moonorm.Model` is\n// generated from these annotations into `" +
    st.format("models") +
    ".g.mbt` on build.\n"
  let mut migrate = "// Code generated by moonctl from the `.api` spec. DO NOT EDIT.\n"
  for t in spec.types {
    let fields = @api.flat_fields(t, spec.types)
    let table = @text.to_snake(t.name)
    let pairs : Array[OrmField] = []
    for f in fields {
      pairs.push(orm_plain_field(f.mbt_name(), f.type_))
    }
    let has_key = fields.any(f => {
      f.mbt_name() == "id" && @model.storage_class(f.type_) is Some(_)
    })
    models = models +
      "\n" +
      orm_struct(
        t.name,
        table,
        "`" +
        t.name +
        "` table, from the `.api` `type` block of the " +
        spec.service +
        " service.",
        pairs,
        if has_key {
          "id"
        } else {
          ""
        },
        Map([]),
      )
    if has_key {
      migrate = migrate +
        "\n" +
        @model.migration_updown(table, t.name + "::model()")
    }
  }
  orm_tree(
    spec.service,
    st,
    dir,
    models,
    if @text.ends_with(migrate, "DO NOT EDIT.\n") {
      ""
    } else {
      migrate
    },
    "",
  )
}

///|
/// The `(table, column)` a foreign key points at, taking the referenced table's
/// single-column primary key when the DDL named no column.
fn ddl_fk_target(
  fk : @model.DdlForeignKey,
  parent : @model.DdlTable,
) -> String? {
  match fk.ref_columns {
    [one, ..] => Some(one)
    [] => parent_pk(parent)
  }
}

///|
/// The single-column primary key of a table, or `None` for a table with none or a
/// composite one — the only shape a relation can hang on without an explicit key.
fn parent_pk(t : @model.DdlTable) -> String? {
  let pks : Array[String] = []
  for c in t.columns {
    if c.primary_key {
      pks.push(c.name)
    }
  }
  match pks {
    [one] => Some(one)
    _ => None
  }
}

///|
/// Whether `t` has a column called `name`.
fn has_column(t : @model.DdlTable, name : String) -> Bool {
  for c in t.columns {
    if c.name == name {
      return true
    }
  }
  false
}

///|
/// The table `name` names, comparing case-insensitively the way SQL does.
fn find_table(
  tables : Array[@model.DdlTable],
  name : String,
) -> @model.DdlTable? {
  let low = name.to_lower()
  for t in tables {
    if t.name.to_lower() == low {
      return Some(t)
    }
  }
  None
}

///|
/// The name a `belongs_to` relation takes: the key column with the suffix a key
/// column wears taken off, so `team_id` is `team` and `country_code` is `country`.
/// A column whose name carries no such suffix keeps it, and the caller adds `_ref`
/// when that would collide with the column itself.
fn relation_name(column : String) -> String {
  for suffix in ["_id", "_key", "_code", "_no", "_uuid"] {
    if @text.ends_with(column, suffix) && column.length() > suffix.length() {
      return column[0:column.length() - suffix.length()].to_owned()
    }
  }
  column
}

///|
/// `value`, or `fallback` when it is `None`.
fn or_default(value : String?, fallback : String) -> String {
  match value {
    Some(v) => v
    None => fallback
  }
}

///|
/// The `#orm.has_many` and `#orm.belongs_to` annotations a SQL schema implies, per
/// table. A foreign key names both sides: the referencing table gets a `belongs_to`
/// (named after the column, `team_id` → `team`) and the referenced one a `has_many`
/// (named after the referencing table). A key onto a table the schema does not
/// declare is left out — an annotation can only point at a type in the same file —
/// and so is a composite key, which has no single field to hang a relation on.
fn ddl_relations(tables : Array[@model.DdlTable]) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = Map([])
  // The names already given to a relation on each table, so two keys onto the same
  // table do not both claim `posts`.
  let taken : Map[String, Array[String]] = Map([])
  for t in tables {
    out.set(t.name, [])
    taken.set(t.name, [])
  }
  for t in tables {
    let child = @text.to_pascal(t.name)
    for fk in t.foreign_keys {
      if fk.columns.length() != 1 {
        continue
      }
      let parent = match find_table(tables, fk.ref_table) {
        Some(p) => p
        None => continue
      }
      let column = fk.columns[0]
      let target = match ddl_fk_target(fk, parent) {
        Some(c) => c
        None => continue
      }
      let key_note = if target == or_default(parent_pk(parent), "") {
        ""
      } else {
        ", key=" + @text.quote(target)
      }
      // The referenced side: `<Parent>::<child table>()`.
      let many = out.get(parent.name).unwrap()
      let many_taken = taken.get(parent.name).unwrap()
      let mut many_name = t.name
      if many_taken.contains(many_name) || has_column(parent, many_name) {
        many_name = many_name + "_list"
      }
      many_taken.push(many_name)
      many.push(
        "#orm.has_many(name=" +
        @text.quote(many_name) +
        ", target=" +
        @text.quote(child) +
        ", foreign_key=" +
        @text.quote(column) +
        key_note +
        ")",
      )
      // The referencing side: `<Child>::<column without its key suffix>()`.
      let one = out.get(t.name).unwrap()
      let one_taken = taken.get(t.name).unwrap()
      let mut one_name = relation_name(column)
      if one_taken.contains(one_name) || has_column(t, one_name) {
        one_name = one_name + "_ref"
      }
      one_taken.push(one_name)
      one.push(
        "#orm.belongs_to(name=" +
        @text.quote(one_name) +
        ", target=" +
        @text.quote(@text.to_pascal(parent.name)) +
        ", foreign_key=" +
        @text.quote(column) +
        key_note +
        ")",
      )
    }
  }
  out
}

///|
/// The `#orm.index` annotations a table's DDL asked for: one per `CREATE INDEX`,
/// `UNIQUE`/`KEY` constraint or column-level `UNIQUE`. `column=` is repeated once
/// per column, the shape `#orm.index` reads.
fn ddl_index_notes(t : @model.DdlTable) -> Array[String] {
  let out : Array[String] = []
  for ix in t.indexes {
    let parts : Array[String] = []
    for c in ix.columns {
      parts.push("column=" + @text.quote(c))
    }
    let mut note = "#orm.index(" + parts.join(", ")
    if ix.name != "" {
      note = note + ", name=" + @text.quote(ix.name)
    }
    if ix.unique {
      note = note + ", unique=true"
    }
    out.push(note + ")")
  }
  out
}

///|
/// The annotated models, migrations and CRUD helpers for a SQL schema. The table
/// and column names are the schema's; a nullable column is declared optional, so
/// `#orm` reads it as one. The schema's indexes become `#orm.index`, and each
/// foreign key a pair of relations — `#orm.has_many` on the referenced table,
/// `#orm.belongs_to` on the referencing one.
pub fn generate_orm_tree_from_ddl(
  tables : Array[@model.DdlTable],
  module_ : String,
  style? : @style.Style,
  dir~ : String = "",
) -> Array[TreeFile] {
  let st = style.unwrap_or(@style.Style::gozero())
  let mut models = "// Code generated by moonctl from the SQL schema. DO NOT EDIT.\n//\n// Each struct is a table: `#orm.table` names it, and the `@moonorm.Model` is\n// generated from these annotations into `" +
    st.format("models") +
    ".g.mbt` on build.\n"
  let mut migrate = "// Code generated by moonctl from the SQL schema. DO NOT EDIT.\n"
  let mut crud = "// Code generated by moonctl from the SQL schema. DO NOT EDIT.\n"
  let relations = ddl_relations(tables)
  for t in tables {
    let name = @text.to_pascal(t.name)
    let pairs : Array[OrmField] = []
    let defaults : Map[String, String] = Map([])
    let mut key = ""
    for c in t.columns {
      let fk = @model.ddl_fk_of(t, c.name)
      let reference = match fk {
        Some(f) => {
          let target = match f.ref_columns {
            [one, ..] => one
            [] =>
              match find_table(tables, f.ref_table) {
                Some(p) => or_default(parent_pk(p), "")
                None => ""
              }
          }
          if target == "" {
            ""
          } else {
            f.ref_table + "." + target
          }
        }
        None => ""
      }
      pairs.push({
        name: c.name,
        ty: ddl_field_type(c),
        unique: c.unique,
        references: reference,
        on_delete: match fk {
          Some(f) => f.on_delete
          None => ""
        },
        on_update: match fk {
          Some(f) => f.on_update
          None => ""
        },
      })
      if c.primary_key && key == "" {
        key = c.name
      }
      match c.default_ {
        Some(text) => defaults.set(c.name, text)
        None => ()
      }
    }
    models = models +
      "\n" +
      orm_struct(
        name,
        t.name,
        "`" + t.name + "` table.",
        pairs,
        key,
        defaults,
        indexes=ddl_index_notes(t),
        relations=relations.get(t.name).unwrap(),
      )
    migrate = migrate + "\n" + @model.migration_for(t, name + "::model()")
    crud = crud +
      "\n" +
      @model.crud_for(t, name + "::model()", nullable_aware=true)
  }
  orm_tree(module_, st, dir, models, migrate, crud)
}

///|
/// The MoonBit type a column is declared as in the annotated tree: a nullable
/// column is optional, which is how `#orm` spells `NULL`. The flat generator keeps
/// the column's own type and says `nullable` on the model instead; here the type
/// carries it, so a `None` has to be bound as SQL `NULL` — which is what
/// `nullable_aware` asks `crud_for` for.
fn ddl_field_type(c : @model.DdlColumn) -> String {
  if c.nullable && !c.primary_key {
    c.type_ + "?"
  } else {
    c.type_
  }
}
