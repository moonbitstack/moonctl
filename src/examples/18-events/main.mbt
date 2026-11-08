///|
/// One spec, three answers to the same route. `returns (stream T)` says the reply
/// never ends in one body: the `api` generator registers the route on `app.stream`
/// and opens a `text/event-stream`, the `gql` one makes it a `#gql.subscription`
/// whose type is the list of events, and the OpenAPI document answers
/// `text/event-stream` instead of a JSON body. The spec also asks for plural tables
/// and camel-cased columns, which the model generator honours.
///
///     moon run src/examples/18-events
#coverage.skip
fn main raise {
  let source =
    #|info (
    #|  title:        "feed"
    #|  tableNaming:  plural_snake
    #|  columnNaming: camel
    #|)
    #|
    #|type Tick {
    #|  id:         int64
    #|  at:         int64
    #|  created_at: int64
    #|  payload:    bytes
    #|  labels:     map[string]string
    #|}
    #|
    #|service feed {
    #|  @doc "each tick as it happens"
    #|  @handler watch
    #|  get /watch returns (stream Tick)
    #|}
  let spec = @moonctl.parse(source)

  // The api generator: the route is a stream, so its handler answers a Stream and
  // the stub opens an event stream rather than one body.
  let app = @moonctl.generate(spec)
  println("--- the api generator ---")
  for line in app.split("\n") {
    if line.contains("app.stream") ||
      line.contains("moonapi.Stream") ||
      line.contains("moonapi.sse") {
      println(line)
    }
  }

  // The gql generator: the same route is a subscription, one event per connection.
  let schema = @moonctl.generate_gql(spec)
  println("\n--- the gql generator ---")
  for line in schema.split("\n") {
    if line.contains("Subscription") || line.contains("subscription.field") {
      println(line)
    }
  }

  // The document: `text/event-stream`, not `application/json`.
  let doc = @moonctl.generate_doc(spec)
  println("\n--- the OpenAPI document ---")
  for line in doc.split("\n") {
    if line.contains("event-stream") || line.contains("\"/watch\"") {
      println(line)
    }
  }

  // The model a SQL schema would make of the same type block: plural table, camel
  // columns, and the bytes and map fields kept out of the row.
  let models = @moonctl.generate_model(spec)
  println("\n--- the model generator ---")
  for line in models.split("\n") {
    if line.contains("ticks") ||
      line.contains("createdAt") ||
      line.contains("Bytes") ||
      line.contains("Map[") {
      println(line)
    }
  }
}
