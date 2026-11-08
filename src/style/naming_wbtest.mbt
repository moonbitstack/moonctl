///|
test "a name is spelled in each casing" {
  assert_eq(Naming::Snake.spell("created_at"), "created_at")
  assert_eq(Naming::Camel.spell("created_at"), "createdAt")
  assert_eq(Naming::Pascal.spell("created_at"), "CreatedAt")
  assert_eq(Naming::Kebab.spell("created_at"), "created-at")
  assert_eq(Naming::ScreamingSnake.spell("created_at"), "CREATED_AT")
  // a name already run together splits before its capitals
  assert_eq(Naming::Snake.spell("blogPost"), "blog_post")
  assert_eq(Naming::Camel.spell("BlogPost"), "blogPost")
}

///|
test "a table is named for one row, or for the set" {
  let one = { ..default_naming, table: Pascal, }
  assert_eq(NamingPolicy::table_name(one, "BlogPost"), "BlogPost")
  let many = { ..default_naming, table: Snake, plural: true, }
  assert_eq(NamingPolicy::table_name(many, "User"), "users")
  // the plural is the last word's: `blog_posts`, not `blogs_posts`
  assert_eq(NamingPolicy::table_name(many, "BlogPost"), "blog_posts")
  // an sibilant takes `es`, a consonant plus `y` takes `ies`
  assert_eq(NamingPolicy::table_name(many, "Address"), "addresses")
  assert_eq(NamingPolicy::table_name(many, "Category"), "categories")
  // a name the rules cannot pluralise is spelled by asking for plain snake
  let plain = { ..default_naming, table: Snake, plural: false, }
  assert_eq(NamingPolicy::table_name(plain, "News"), "news")
}

///|
test "a column is spelled on its own, apart from the field" {
  let camel = { ..default_naming, column: Camel, }
  assert_eq(NamingPolicy::column_name(camel, "created_at"), "createdAt")
  assert_eq(
    NamingPolicy::column_name(default_naming, "created_at"),
    "created_at",
  )
}

///|
test "the policy comes from the spec's info block, and only when it says so" {
  // nothing said: the generators keep their own spelling
  assert_eq(NamingPolicy::of_info([]) is None, true)
  assert_eq(NamingPolicy::of_info([("title", "shop")]) is None, true)
  // said: read, both spellings of the key
  let asked = NamingPolicy::of_info([
    ("tableNaming", "plural_snake"),
    ("columnNaming", "camel"),
  ])
  assert_eq(asked is Some(_), true)
  match asked {
    Some(policy) => {
      assert_eq(NamingPolicy::table_name(policy, "Order"), "orders")
      assert_eq(NamingPolicy::column_name(policy, "created_at"), "createdAt")
    }
    None => abort("the policy was asked for and not read")
  }
  // `tablePlural` on its own is enough to be asked for
  assert_eq(NamingPolicy::of_info([("tablePlural", "true")]) is Some(_), true)
}

///|
test "a naming value that is not a casing is reported, not guessed" {
  assert_eq(naming_problems([]).length(), 0)
  assert_eq(
    naming_problems([("tableNaming", "kebab"), ("columnNaming", "camel")]).length(),
    0,
  )
  let bad = naming_problems([("tableNaming", "snak"), ("tablePlural", "yes")])
  assert_eq(bad.length(), 2)
  assert_eq(bad[0].contains("want snake, camel, pascal"), true)
  assert_eq(bad[1].contains("want true or false"), true)
}
