///|
test "an api type becomes an annotated table, with the model left to build" {
  let spec = @api.parse(
    (
      #|type Item {
      #|  id: int64
      #|  name: string
      #|  price: float64
      #|}
      #|
      #|service shop {
      #|  get /items list
      #|}
    ),
  )
  let tree = generate_orm_tree(spec)
  let models = tree_at(tree, "internal/model/models.mbt")
  assert_eq(contains(models, "#orm.table(name=\"item\")"), true)
  assert_eq(contains(models, "pub(all) struct Item {"), true)
  // `id` is the key, and it is not declared `autoincrement`: the type is not
  // optional, so the caller supplies it
  assert_eq(
    contains(models, "  #orm.column(primary_key=true)\n  id : Int64"),
    true,
  )
  assert_eq(contains(models, "autoincrement"), false)
  // and nothing is hand-built: no `Model::new`, no row decoder
  assert_eq(contains(models, "Model::new"), false)
  assert_eq(contains(models, "row =>"), false)
}

///|
test "the model module is wired to the generator that reads those annotations" {
  let spec = @api.parse(
    (
      #|type Item {
      #|  id: int64
      #|}
      #|
      #|service shop {
      #|  get /items list
      #|}
    ),
  )
  let tree = generate_orm_tree(spec)
  let mod_ = tree_at(tree, "moon.mod")
  assert_eq(contains(mod_, "name = \"shop\""), true)
  assert_eq(contains(mod_, pinned("moonbitstack/moonorm")), true)
  assert_eq(contains(mod_, "moonx moonbitstack/moonorm/cmd/orm@"), true)
  // the rule is long enough that the formatter keeps it one argument per line
  assert_eq(contains(mod_, "rule(\n  name: \"orm\",\n  command: "), true)
  let pkg = tree_at(tree, "internal/model/moon.pkg")
  assert_eq(
    contains(
      pkg, "dev_build(rule: \"orm\", input: \"models.mbt\", output: \"models.g.mbt\")",
    ),
    true,
  )
  // the generated file is exempt from the formatter, or `moon fmt` would rewrite it
  assert_eq(contains(pkg, "formatter(ignore: [ \"models.g.mbt\" ])"), true)
}

///|
test "a field with no column is skipped, and its table still builds" {
  let spec = @api.parse(
    (
      #|type Inner {
      #|  a: int
      #|}
      #|
      #|type Q {
      #|  id: int64
      #|  inner: Inner
      #|  tags: []string
      #|}
      #|
      #|service shop {
      #|  get /q q
      #|}
    ),
  )
  let models = tree_at(generate_orm_tree(spec), "internal/model/models.mbt")
  // skipped fields keep the struct compiling: `#orm.skip` fills them from Default
  assert_eq(contains(models, "  #orm.skip\n  inner : Inner"), true)
  assert_eq(contains(models, "  #orm.skip\n  tags : Array[String]"), true)
  // ...which the type has to have
  assert_eq(contains(models, "#derive(Default)"), true)
  assert_eq(contains(models, "pub extend Q with Default::{default}"), true)
  // a table with nothing skipped needs neither
  assert_eq(contains(models, "pub extend Inner with Default"), false)
}

///|
test "an Int32 column says which SQL kind it wants, and an optional one may be auto" {
  let spec = @api.parse(
    (
      #|type Row {
      #|  id: int64
      #|  count: int
      #|}
      #|
      #|service shop {
      #|  get /rows rows
      #|}
    ),
  )
  let models = tree_at(generate_orm_tree(spec), "internal/model/models.mbt")
  // `Int32` has no default column in moonorm; `Int64` does (a bigint)
  assert_eq(
    contains(models, "  #orm.column(kind=\"int\")\n  count : Int32"),
    true,
  )
}

///|
test "only a table with a key gets a migration" {
  let spec = @api.parse(
    (
      #|type WithKey {
      #|  id: int64
      #|  name: string
      #|}
      #|
      #|type NoKey {
      #|  name: string
      #|}
      #|
      #|service shop {
      #|  get /a a
      #|}
    ),
  )
  let tree = generate_orm_tree(spec)
  let migrate = tree_at(tree, "internal/model/migrate.mbt")
  assert_eq(
    contains(migrate, "sess.create_table(WithKey::model(), if_not_exists=true)"),
    true,
  )
  assert_eq(contains(migrate, "NoKey::model()"), false)
}

///|
test "a spec with no tables generates no migrations, and imports only the library" {
  let spec = @api.parse("service shop {\n  get /ping ping\n}")
  let tree = generate_orm_tree(spec)
  // nothing to migrate: the file is not written at all
  assert_eq(tree.any(f => f.path == "internal/model/migrate.mbt"), false)
  let pkg = tree_at(tree, "internal/model/moon.pkg")
  assert_eq(contains(pkg, "moonbitstack/moonorm"), true)
  // `moondb` is read by the migrations and the CRUD helpers, and there are none
  assert_eq(contains(pkg, "moonbitstack/moondb"), false)
}

///|
test "a nullable column is optional, and its CRUD binds None as NULL" {
  let tables = @model.parse_ddl(
    (
      #|CREATE TABLE orders (
      #|  id     BIGINT PRIMARY KEY,
      #|  note   TEXT,
      #|  amount REAL NOT NULL
      #|);
    ),
  )
  let tree = generate_orm_tree_from_ddl(tables, "shop")
  let models = tree_at(tree, "internal/model/models.mbt")
  // the type carries the nullability, which is how `#orm` spells `NULL`
  assert_eq(contains(models, "  note : String?"), true)
  assert_eq(contains(models, "  amount : Double\n"), true)
  assert_eq(contains(models, "  id : Int64\n"), true)
  let crud = tree_at(tree, "internal/model/crud.mbt")
  // `None` has to travel as SQL NULL, or an update would blank the column
  assert_eq(contains(crud, "match record.note {"), true)
  assert_eq(contains(crud, "Some(v) => @moondb.Text(v)"), true)
  assert_eq(contains(crud, "None => @moondb.Null"), true)
  // a column that cannot be null is bound directly
  assert_eq(
    contains(crud, ".set(\"amount\", @moondb.Double(record.amount))"),
    true,
  )
}

///|
test "a SQL default travels onto the annotation" {
  let tables = @model.parse_ddl(
    (
      #|CREATE TABLE jobs (
      #|  id    BIGINT PRIMARY KEY,
      #|  tries INTEGER NOT NULL DEFAULT 0
      #|);
    ),
  )
  let models = tree_at(
    generate_orm_tree_from_ddl(tables, "shop"),
    "internal/model/models.mbt",
  )
  assert_eq(
    contains(models, "  #orm.column(kind=\"int\", default=\"0\")"),
    true,
  )
}

///|
test "the CRUD helpers read through the generated model, not a hand-built one" {
  let tables = @model.parse_ddl(
    "CREATE TABLE jobs (\n  id BIGINT PRIMARY KEY,\n  name TEXT NOT NULL\n);\n",
  )
  let crud = tree_at(
    generate_orm_tree_from_ddl(tables, "shop"),
    "internal/model/crud.mbt",
  )
  assert_eq(contains(crud, "sess.insert_record(Jobs::model(), record)"), true)
  assert_eq(contains(crud, "sess.all(Jobs::model())"), true)
  assert_eq(contains(crud, "jobs_model"), false)
  // the module is named after the caller, not the schema
  let mod_ = tree_at(generate_orm_tree_from_ddl(tables, "shop"), "moon.mod")
  assert_eq(contains(mod_, "name = \"shop\""), true)
}

///|
test "the flat generators are untouched by the annotated tree" {
  // `--flat` writes the hand-built model, which is what a project with no module
  // of its own needs
  let spec = @api.parse(
    "type Item {\n  id: int64\n}\n\nservice shop {\n  get /i i\n}\n",
  )
  let code = @model.generate_model(spec)
  assert_eq(
    contains(
      code, "pub let item_model : @moonorm.Model[Item] = @moonorm.Model::new(",
    ),
    true,
  )
  assert_eq(contains(code, "#orm.table"), false)
}

///|
/// A schema with two tables, an index on the referencing one, and a foreign key
/// between them.
let related_schema : Array[@model.DdlTable] = @model.parse_ddl(
  (
    #|CREATE TABLE teams (
    #|  id   INTEGER PRIMARY KEY,
    #|  name TEXT NOT NULL UNIQUE
    #|);
    #|
    #|CREATE TABLE heroes (
    #|  id      INTEGER PRIMARY KEY,
    #|  team_id INTEGER NOT NULL,
    #|  code    TEXT,
    #|  CONSTRAINT fk_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE
    #|);
    #|
    #|CREATE UNIQUE INDEX uq_hero_code ON heroes (code);
    #|CREATE INDEX ix_hero_team ON heroes (team_id);
  ),
)

///|
test "an index in the schema is an index annotation on the table" {
  let models = tree_at(
    generate_orm_tree_from_ddl(related_schema, "shop"),
    "internal/model/models.mbt",
  )
  assert_eq(
    contains(
      models, "#orm.index(column=\"code\", name=\"uq_hero_code\", unique=true)\n#orm.index(column=\"team_id\", name=\"ix_hero_team\")\n",
    ),
    true,
  )
  // the index annotations sit above the struct they belong to
  assert_eq(contains(models, "#orm.index"), true)
  // a table with no index keeps none
  assert_eq(contains(models, "#orm.index(column=\"name\")"), false)
}

///|
test "a column UNIQUE is the column's annotation" {
  let models = tree_at(
    generate_orm_tree_from_ddl(related_schema, "shop"),
    "internal/model/models.mbt",
  )
  assert_eq(
    contains(models, "  #orm.column(unique=true)\n  name : String\n"),
    true,
  )
}

///|
test "a foreign key becomes a relation on both sides" {
  let models = tree_at(
    generate_orm_tree_from_ddl(related_schema, "shop"),
    "internal/model/models.mbt",
  )
  // the referenced side holds the many
  assert_eq(
    contains(
      models, "#orm.has_many(name=\"heroes\", target=\"Heroes\", foreign_key=\"team_id\")",
    ),
    true,
  )
  // the referencing side holds the one, named after its column
  assert_eq(
    contains(
      models, "#orm.belongs_to(name=\"team\", target=\"Teams\", foreign_key=\"team_id\")",
    ),
    true,
  )
  // and the column itself carries the constraint, so the DDL it creates has it
  assert_eq(
    contains(
      models, "  #orm.column(kind=\"int\", references=\"teams.id\", on_delete=\"CASCADE\")",
    ),
    true,
  )
}

///|
test "two keys onto one table get two names, and a key onto a stranger is left out" {
  let tables = @model.parse_ddl(
    (
      #|CREATE TABLE users (
      #|  id INTEGER PRIMARY KEY
      #|);
      #|
      #|CREATE TABLE posts (
      #|  id        INTEGER PRIMARY KEY,
      #|  author_id INTEGER REFERENCES users(id),
      #|  editor_id INTEGER REFERENCES users(id),
      #|  owner_id  INTEGER REFERENCES elsewhere(id)
      #|);
    ),
  )
  let models = tree_at(
    generate_orm_tree_from_ddl(tables, "shop"),
    "internal/model/models.mbt",
  )
  // both keys are named after their column, so neither collides with the other
  assert_eq(
    contains(
      models, "#orm.belongs_to(name=\"author\", target=\"Users\", foreign_key=\"author_id\")",
    ),
    true,
  )
  assert_eq(
    contains(
      models, "#orm.belongs_to(name=\"editor\", target=\"Users\", foreign_key=\"editor_id\")",
    ),
    true,
  )
  // both appear on the same table, so the referenced side holds both
  assert_eq(
    contains(
      models, "#orm.has_many(name=\"posts\", target=\"Posts\", foreign_key=\"author_id\")",
    ),
    true,
  )
  assert_eq(
    contains(
      models, "#orm.has_many(name=\"posts_list\", target=\"Posts\", foreign_key=\"editor_id\")",
    ),
    true,
  )
  // a key onto a table the schema does not declare is a column constraint only
  assert_eq(contains(models, "target=\"Elsewhere\""), false)
}

///|
test "a key onto a non-key column says which column it joins on" {
  let tables = @model.parse_ddl(
    (
      #|CREATE TABLE countries (
      #|  id   INTEGER PRIMARY KEY,
      #|  code TEXT NOT NULL
      #|);
      #|
      #|CREATE TABLE cities (
      #|  id           INTEGER PRIMARY KEY,
      #|  country_code TEXT REFERENCES countries(code)
      #|);
    ),
  )
  let models = tree_at(
    generate_orm_tree_from_ddl(tables, "shop"),
    "internal/model/models.mbt",
  )
  assert_eq(
    contains(
      models, "#orm.belongs_to(name=\"country\", target=\"Countries\", foreign_key=\"country_code\", key=\"code\")",
    ),
    true,
  )
  assert_eq(
    contains(
      models, "#orm.has_many(name=\"cities\", target=\"Cities\", foreign_key=\"country_code\", key=\"code\")",
    ),
    true,
  )
}
