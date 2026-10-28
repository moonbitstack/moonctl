///|
/// A plugin's reply is arbitrary text from another process, so every fault it can
/// hand back is covered here: a path that escapes the output directory, the same
/// path twice, and a reply that is not the shape the protocol promises.

///|
test "a path inside the output directory is written" {
  assert_eq(safe_path("handler/user.mbt"), true)
  assert_eq(safe_path("handler\\user.mbt"), true)
  assert_eq(safe_path("./handler/user.mbt"), true)
  assert_eq(safe_path("a.b.c"), true)
}

///|
test "a path that escapes the output directory is refused" {
  // absolute, either separator, either platform's spelling
  assert_eq(safe_path("/etc/passwd"), false)
  assert_eq(safe_path("\\\\server\\share\\x.mbt"), false)
  assert_eq(safe_path("C:/Windows/system32/x.mbt"), false)
  assert_eq(safe_path("c:x.mbt"), false)
  // or relative, climbing out
  assert_eq(safe_path("../x.mbt"), false)
  assert_eq(safe_path("a/../../x.mbt"), false)
  assert_eq(safe_path("a\\..\\x.mbt"), false)
  assert_eq(safe_path(".."), false)
  // and an empty path is not a path
  assert_eq(safe_path(""), false)
  assert_eq(safe_path("   "), false)
}

///|
test "the plan keeps the first copy of a path and reports the rest" {
  let files : Array[GenFile] = [
    { path: "handler/user.mbt", content: "one", },
    { path: "../escape.mbt", content: "two", },
    { path: "handler/user.mbt", content: "three", },
    { path: "handler/order.mbt", content: "four", },
  ]
  let (kept, refused) = plugin_plan(files)
  assert_eq(kept.length(), 2)
  assert_eq(kept[0].path, "handler/user.mbt")
  // the first copy wins, so the output does not depend on the order the plugin
  // happened to write in
  assert_eq(kept[0].content, "one")
  assert_eq(kept[1].path, "handler/order.mbt")
  assert_eq(refused.length(), 2)
  assert_eq(
    refused[0],
    "refused ../escape.mbt: a plugin may only write inside the output directory",
  )
  assert_eq(refused[1], "refused handler/user.mbt: the plugin wrote it twice")
}

///|
test "a plugin that produces nothing writes nothing" {
  let (kept, refused) = plugin_plan([])
  assert_eq(kept.length(), 0)
  assert_eq(refused.length(), 0)
}

///|
test "a reply that is not a file list yields no files" {
  // the shapes a broken plugin actually emits
  assert_eq(parse_gen_files(@json.loads("null")).length(), 0)
  assert_eq(parse_gen_files(@json.loads("{}")).length(), 0)
  assert_eq(parse_gen_files(@json.loads("\"a string\"")).length(), 0)
  assert_eq(parse_gen_files(@json.loads("[1, 2, 3]")).length(), 0)
  // an element with no path is dropped rather than written to the output directory
  // itself
  let files = parse_gen_files(
    @json.loads("[{\"content\": \"x\"}, {\"path\": \"a.mbt\"}]"),
  )
  assert_eq(files.length(), 1)
  assert_eq(files[0].path, "a.mbt")
  // an element with no content is written empty, which is a legitimate file
  let empty = parse_gen_files(@json.loads("[{\"path\": \"b.mbt\"}]"))
  assert_eq(empty.length(), 1)
  assert_eq(empty[0].content, "")
}
