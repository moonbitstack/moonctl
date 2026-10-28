///|
/// `mctl model mongo`: a `.api` `type` block as the document a collection stores,
/// and a typed repository over a collection port — no driver in sight.
///
/// The spec below is the shape a Mongo user actually has: an `id`, an optional
/// field, a list, and a nested type. The generator turns each block into a `Doc`
/// (derived both ways, so a value round-trips without a hand-written field walker)
/// and a `Repo` whose five calls are the five a driver serves.
///
///     moon run src/examples/15-mongo
#coverage.skip
fn main raise {
  let source =
    #|service catalog {
    #|  @handler ping
    #|  get /ping
    #|}
    #|
    #|type Product {
    #|  id: int64 `json:"id"`
    #|  name: string `json:"name"`
    #|  price: float64 `json:"price"`
    #|  tags: []string `json:"tags"`
    #|  note: string `json:"note,optional"`
    #|  maker: Maker `json:"maker"`
    #|}
    #|
    #|type Maker {
    #|  id: int64 `json:"id"`
    #|  name: string `json:"name"`
    #|}
  let spec = @moonctl.parse(source)
  let model = @moonctl.generate_mongo(spec)
  println("document model: " + model.length().to_string() + " bytes")
  println("file: " + @moonctl.mongo_file_name(spec.service))
  println("")
  // The port, then the document, then the repository: the three things a reader
  // needs to see.
  for
    anchor in [
      "pub(all) struct Collection {", "pub(all) struct ProductDoc {", "pub(all) struct ProductRepo {",
      "pub fn ProductRepo::find(", "pub fn ProductRepo::delete(",
    ] {
    println("---- " + anchor)
    println(excerpt(model, anchor, 8))
  }
  // A nested type is nested as a document, not as the wire type: the derived
  // conversions only line up if the field is a document too.
  println("---- nested")
  println(
    "  maker : MakerDoc is in the output: " +
    contains(model, "  maker : MakerDoc\n").to_string(),
  )
  println("")
  println("the spec declares " + spec.types.length().to_string() + " documents")
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
/// Whether `hay` contains `needle`.
fn contains(hay : String, needle : String) -> Bool {
  at_of(hay, needle) >= 0
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
