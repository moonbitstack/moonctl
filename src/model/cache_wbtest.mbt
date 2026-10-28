///|
test "a table with a key gets read-through, invalidate and evict" {
  let out = generate_cached(
    @api.parse(
      (
        #|service greet {
        #|    @handler ping
        #|    get /ping
        #|}
        #|
        #|type User {
        #|    id: int64 `json:"id"`
        #|    name: string `json:"name"`
        #|}
      ),
    ),
  )
  // the port is generic, so a cache holds records and nothing is serialised
  assert_eq(has(out, "pub(all) struct Cache[T] {"), true)
  assert_eq(has(out, "pub fn[T] memory_cache() -> Cache[T] {"), true)
  assert_eq(has(out, "pub(all) suberror CacheError {"), true)
  // one key function per table, named after the table
  assert_eq(has(out, "pub fn user_cache_key(id : Int64) -> String {"), true)
  assert_eq(has(out, "\"users:\" + id.to_string()"), true)
  // read-through: a failed read is a miss, a hit skips the loader
  assert_eq(has(out, "pub fn user_find_cached("), true)
  assert_eq(has(out, "cache : Cache[User],"), true)
  assert_eq(has(out, "load : (Int64) -> User? raise CacheError,"), true)
  assert_eq(
    has(out, "let hit : User? = (cache.get)(key) catch { _ => None }"),
    true,
  )
  // write and delete go through, then drop the cached copy
  assert_eq(has(out, "pub fn user_write_cached("), true)
  assert_eq(has(out, "pub fn user_evict_cached("), true)
  assert_eq(has(out, "save(record)"), true)
  assert_eq(has(out, "remove(id)"), true)
  // the write path drops the key of the record it just wrote, the evict path the one
  // it just deleted
  assert_eq(has(out, "(cache.del)(user_cache_key(record.id))"), true)
  assert_eq(has(out, "(cache.del)(user_cache_key(id))"), true)
}

///|
test "a table whose fields are all lists has no key, so no layer" {
  let out = generate_cached(
    @api.parse(
      (
        #|service blobs {
        #|    @handler ping
        #|    get /ping
        #|}
        #|
        #|type Blob {
        #|    parts: [][]byte `json:"parts"`
        #|}
      ),
    ),
  )
  assert_eq(has(out, "pub(all) struct Cache[T] {"), true)
  assert_eq(has(out, "blob_find_cached"), false)
}

///|
test "the file is named after the service, and an empty spec says so" {
  assert_eq(cache_file_name("greet"), "greet_cache.mbt")
  assert_eq(cache_file_name(""), "model_cache.mbt")
  let empty = generate_cached(
    @api.parse(
      (
        #|service greet {
        #|    @handler ping
        #|    get /ping
        #|}
      ),
    ),
  )
  assert_eq(has(empty, "there is nothing to cache."), true)
  assert_eq(has(empty, "_cached("), false)
}
