///|
/// Whether `hay` contains `needle`.
fn has(hay : String, needle : String) -> Bool {
  @text.index_of_str(hay, needle) >= 0
}

///|
test "a type block becomes a table with its id as the key" {
  let source =
    #|service greet {
    #|    @handler ping
    #|    get /ping
    #|}
    #|
    #|type User {
    #|    id: int64 `json:"id"`
    #|    name: string `json:"name"`
    #|    nickname: string `json:"nickname,optional"`
    #|    tags: []string `json:"tags"`
    #|}
  let sql = generate_migrations(@api.parse(source))
  assert_eq(has(sql, "-- mctl migrate: greet"), true)
  assert_eq(has(sql, "CREATE TABLE IF NOT EXISTS `users` ("), true)
  assert_eq(has(sql, "`id` BIGINT NOT NULL"), true)
  assert_eq(has(sql, "`name` VARCHAR(191) NOT NULL"), true)
  // `optional` is what makes a column nullable
  assert_eq(has(sql, "`nickname` VARCHAR(191) NULL"), true)
  // a list has no column type, so it is stored as JSON
  assert_eq(has(sql, "`tags` JSON NOT NULL"), true)
  assert_eq(has(sql, "PRIMARY KEY (`id`)"), true)
  assert_eq(has(sql, ");"), true)
}

///|
test "the file is named after the service, and an empty spec says so" {
  assert_eq(migrate_file_name("greet"), "greet_migrate.sql")
  assert_eq(migrate_file_name(""), "schema_migrate.sql")
  let empty = generate_migrations(
    @api.parse(
      (
        #|service greet {
        #|    @handler ping
        #|    get /ping
        #|}
      ),
    ),
  )
  assert_eq(has(empty, "nothing to create"), true)
  assert_eq(has(empty, "CREATE TABLE"), false)
}
