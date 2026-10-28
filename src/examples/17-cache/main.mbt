///|
/// `mctl model cache`: the cache-aside layer in front of a table's CRUD — read
/// through on `find`, invalidate on `write` and on `evict`.
///
/// The port is generic, so a cache holds the record itself rather than the text it
/// serialises to, and an in-memory cache is a `Map`: running this example drives the
/// generated layer against one, which is what a test does and what a small service
/// may do in production.
///
///     moon run src/examples/17-cache
#coverage.skip
fn main raise {
  let spec = @moonctl.parse(
    (
      #|service catalog {
      #|  @handler ping
      #|  get /ping
      #|}
      #|
      #|type Product {
      #|  id: int64 `json:"id"`
      #|  name: string `json:"name"`
      #|}
    ),
  )
  let layer = @moonctl.generate_cached(spec)
  println("cache layer: " + layer.length().to_string() + " bytes")
  println("file: " + @moonctl.cache_file_name(spec.service))
  println("")
  for
    anchor in [
      "pub(all) struct Cache[T] {", "pub fn[T] memory_cache() -> Cache[T] {", "pub fn product_cache_key(",
      "pub fn product_find_cached(",
    ] {
    println("---- " + anchor)
    println(excerpt(layer, anchor, 9))
  }
  println("---- what the layer promises")
  println(
    "  a failed cache read falls back to the table: " +
    (at_of(layer, "catch { _ => None }") >= 0).to_string(),
  )
  println(
    "  a write drops the cached copy:            " +
    (at_of(layer, "(cache.del)(") >= 0).to_string(),
  )
  println(
    "  evict does the same for a delete:         " +
    (at_of(layer, "remove(id)") >= 0).to_string(),
  )
}

///|
/// The first index in `hay` where `needle` starts, or `-1`.
fn at_of(hay : String, needle : String) -> Int32 {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut same = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
    }
    if same {
      return i
    }
  }
  -1
}

///|
/// The `lines` lines of `text` that follow the first occurrence of `anchor`.
fn excerpt(text : String, anchor : String, lines : Int32) -> String {
  let at = at_of(text, anchor)
  if at < 0 {
    return anchor + ": not found"
  }
  let mut end = at
  let mut seen = 0
  while end < text.length() && seen < lines {
    if text[end] == '\n' {
      seen = seen + 1
    }
    end = end + 1
  }
  text[at:end].to_owned()
}
