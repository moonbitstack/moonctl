///|
/// The `.api` `type` → moonorm model generator. `generate_model` turns each
/// storable `type` block into a model struct, a `@moonorm.Model[T]` (an `id` column
/// is the primary key, plus the `from_row` decoder and `to_columns` projection
/// MoonBit can't synthesise for want of reflection), a `@moonorm.Table` descriptor,
/// and an up/down migration pair. A block with a non-storable field (here `Feed`'s
/// `[]Post` slice) still gets its struct and a plain `Table`.
///
///     moon run src/examples/04-model
#coverage.skip
fn main raise {
  let source =
    #|type User {
    #|  id:    int64  `json:"id"`
    #|  name:  string `json:"name"`
    #|  email: string `json:"email"`
    #|}
    #|
    #|type Post {
    #|  id:     int64  `json:"id"`
    #|  title:  string `json:"title"`
    #|  author: int64  `json:"author"`
    #|}
    #|
    #|type Feed {
    #|  posts: []Post `json:"posts"`
    #|}
    #|
    #|service blog {
    #|  get /users/:id get_user
    #|}
  let spec = @moonctl.parse(source)
  println(
    "parsed \{spec.types.length()} type blocks for service \{spec.service}\n",
  )
  println("==== generate_model(spec) -> moonorm model + migration ====\n")
  println(@moonctl.generate_model(spec))
}
