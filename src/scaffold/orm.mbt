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
/// key, the SQL kind of a MoonBit type `moonorm` has no default column for, and
/// `autoincrement` on an optional integer key. `None` when the type says it all.
fn orm_annotation(
  ty : String,
  primary_key : Bool,
  default : String?,
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
  match orm_kind(base) {
    Some(kind) => args.push("kind=" + @text.quote(kind))
    None => ()
  }
  match default {
    Some(text) => args.push("default=" + @text.quote(text))
    None => ()
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
) -> String {
  let note = match @model.storage_class(orm_base(ty)) {
    Some(_) =>
      match orm_annotation(ty, primary_key, default) {
        Some(annotation) => "  " + annotation + "\n"
        None => ""
      }
    None => "  #orm.skip\n"
  }
  note + "  " + field + " : " + ty + "\n"
}

///|
/// Whether any field of a struct takes `#orm.skip`, which is what makes
/// `#derive(Default)` necessary.
fn orm_skips(fields : Array[(String, String)]) -> Bool {
  for f in fields {
    if @model.storage_class(orm_base(f.1)) is None {
      return true
    }
  }
  false
}

///|
/// The annotated struct for one table. `table` is the SQL name, `name` the MoonBit
/// type, and `fields` its `(field, type)` pairs in declaration order.
fn orm_struct(
  name : String,
  table : String,
  doc : String,
  fields : Array[(String, String)],
  key : String,
  defaults : Map[String, String],
) -> String {
  let pairs : Array[(String, String)] = []
  for f in fields {
    pairs.push(f)
  }
  let skips = orm_skips(pairs)
  let mut out = "///|\n/// " + doc + "\n"
  if skips {
    out = out + "#derive(Default)\n"
  }
  out = out +
    "#orm.table(name=" +
    @text.quote(table) +
    ")\npub(all) struct " +
    name +
    " {\n"
  for f in pairs {
    let default = defaults.get(f.0)
    out = out + orm_field(f.0, f.1, f.0 == key, default)
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
    let pairs : Array[(String, String)] = []
    for f in fields {
      pairs.push((f.mbt_name(), f.type_))
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
/// The annotated models, migrations and CRUD helpers for a SQL schema. The table
/// and column names are the schema's; a nullable column is declared optional, so
/// `#orm` reads it as one.
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
  for t in tables {
    let name = @text.to_pascal(t.name)
    let pairs : Array[(String, String)] = []
    let defaults : Map[String, String] = Map([])
    let mut key = ""
    for c in t.columns {
      pairs.push((c.name, ddl_field_type(c)))
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
      orm_struct(name, t.name, "`" + t.name + "` table.", pairs, key, defaults)
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
