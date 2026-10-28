///|
test "a type block becomes a document and a typed repository" {
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
  let out = generate_mongo(@api.parse(source))
  // the port, declared once for the whole file
  assert_eq(has(out, "pub(all) struct Collection {"), true)
  assert_eq(
    has(out, "run : (MongoOp, Json, Json) -> Json raise MongoError"),
    true,
  )
  assert_eq(has(out, "pub(all) enum MongoOp {"), true)
  // the document, derived both ways, with the explicit extends that keep the
  // derived methods off the struct
  assert_eq(has(out, "pub(all) struct UserDoc {"), true)
  assert_eq(has(out, "} derive(FromJson, ToJson)"), true)
  assert_eq(
    has(out, "pub extend UserDoc with @json.FromJson::{from_json}"),
    true,
  )
  assert_eq(has(out, "pub extend UserDoc with ToJson::{to_json}"), true)
  assert_eq(has(out, "  id : Int64\n"), true)
  assert_eq(has(out, "  tags : Array[String]\n"), true)
  // `optional` is what makes the key nullable
  assert_eq(has(out, "  nickname : String?\n"), true)
  // the repository is named after the type, over the collection
  assert_eq(has(out, "pub(all) struct UserRepo {"), true)
  assert_eq(
    has(out, "pub fn UserRepo::new(coll : Collection) -> UserRepo {"),
    true,
  )
  assert_eq(
    has(out, "ignore((self.coll.run)(Insert, empty_doc(), @json.to_json(doc)))"),
    true,
  )
  assert_eq(has(out, "pub fn UserRepo::find("), true)
  assert_eq(has(out, "  id : Int64\n) -> UserDoc raise MongoError {"), true)
  assert_eq(has(out, "filter_of(\"id\", @json.to_json(id))"), true)
  assert_eq(
    has(
      out, "raise MongoMissing(collection=self.coll.name, key=id.to_string())",
    ),
    true,
  )
  assert_eq(has(out, "pub fn UserRepo::replace("), true)
  assert_eq(has(out, "pub fn UserRepo::delete("), true)
  assert_eq(has(out, "-> Bool raise MongoError {"), true)
  assert_eq(
    has(out, "pub fn UserRepo::all(self : UserRepo) -> Array[UserDoc]"),
    true,
  )
}

///|
test "no id field falls back to the first single-valued one" {
  let out = generate_mongo(
    @api.parse(
      (
        #|service tags {
        #|    @handler ping
        #|    get /ping
        #|}
        #|
        #|type Tag {
        #|    slug: string `json:"slug"`
        #|    labels: []string `json:"labels"`
        #|}
      ),
    ),
  )
  assert_eq(has(out, "pub fn TagRepo::find("), true)
  assert_eq(has(out, "  slug : String\n) -> TagDoc raise MongoError {"), true)
  assert_eq(has(out, "filter_of(\"slug\", @json.to_json(slug))"), true)
}

///|
test "a document with only lists gets no key-based method" {
  let out = generate_mongo(
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
  assert_eq(has(out, "pub(all) struct BlobDoc {"), true)
  assert_eq(has(out, "pub fn BlobRepo::insert("), true)
  assert_eq(has(out, "pub fn BlobRepo::all("), true)
  // nothing to match a document by, so no find, replace or delete
  assert_eq(has(out, "BlobRepo::find"), false)
  assert_eq(has(out, "BlobRepo::replace"), false)
  assert_eq(has(out, "BlobRepo::delete"), false)
}

///|
test "the file is named after the service, and an empty spec says so" {
  assert_eq(mongo_file_name("greet"), "greet_mongo.mbt")
  assert_eq(mongo_file_name(""), "model_mongo.mbt")
  let empty = generate_mongo(
    @api.parse(
      (
        #|service greet {
        #|    @handler ping
        #|    get /ping
        #|}
      ),
    ),
  )
  assert_eq(has(empty, "there is no document\n// to model."), true)
  assert_eq(has(empty, "Doc {"), false)
  // the port is still declared: an empty spec makes an empty model, not a broken
  // file
  assert_eq(has(empty, "pub(all) struct Collection {"), true)
}

///|
test "a field naming another type nests that type's document" {
  let out = generate_mongo(
    @api.parse(
      (
        #|service orders {
        #|    @handler ping
        #|    get /ping
        #|}
        #|
        #|type Order {
        #|    id: int64 `json:"id"`
        #|    buyer: User `json:"buyer"`
        #|    lines: []Line `json:"lines"`
        #|}
        #|
        #|type User {
        #|    id: int64 `json:"id"`
        #|}
        #|
        #|type Line {
        #|    sku: string `json:"sku"`
        #|}
      ),
    ),
  )
  // a document that nests one nests a document, so the derived conversions hold
  assert_eq(has(out, "  buyer : UserDoc\n"), true)
  assert_eq(has(out, "  lines : Array[LineDoc]\n"), true)
  // and a type nothing models is carried across untouched
  assert_eq(has(out, "UserDoc"), true)
  assert_eq(has(out, "pub(all) struct LineDoc {"), true)
}
