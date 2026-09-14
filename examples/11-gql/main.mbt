///|
/// The `gql` generator — the GraphQL counterpart of `generate` (moonapi) and
/// `generate_grpc` (moonrpc). `generate_gql` turns each `.api` `type` block into a
/// moongql code-first object type (mapping MoonBit scalars to GraphQL scalars, an
/// `Array[T]` to a non-null list, a `Map[...]` to a JSON string), adds a `Query`
/// root with a `<type>(id: ID!)` lookup per type, and emits a resolver stub per
/// field. The output compiles against `moonbitstack/moongql`; fill in the stub bodies.
///
///     moon run examples/11-gql
#coverage.skip
fn main raise {
  let source =
    #|type Author {
    #|  id:   int64  `json:"id"`
    #|  name: string `json:"name"`
    #|}
    #|
    #|type Book {
    #|  id:      int64    `json:"id"`
    #|  title:   string   `json:"title"`
    #|  authors: []Author `json:"authors"`
    #|  price:   double   `json:"price"`
    #|}
    #|
    #|service library {
    #|  get /books/:id get_book
    #|}
  let spec = @moonctl.parse(source)
  println(
    "service \{spec.service}: \{spec.types.length()} type blocks -> GraphQL schema\n",
  )
  println("==== generate_gql(spec) -> moongql schema + resolver stubs ====\n")
  println(@moonctl.generate_gql(spec))
}
