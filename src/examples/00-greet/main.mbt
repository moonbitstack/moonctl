///|
/// From a `.api` spec to code, in one process — the pipeline the `mctl` binary
/// runs, minus the file IO. `parse` reads the spec, `generate` emits the moonapi
/// scaffold, `openapi_document` emits the matching OpenAPI 3.1 document. Pure
/// logic, so it runs on every backend.
///
///     moon run src/examples/00-greet
#coverage.skip
fn main raise {
  let source =
    #|type User {
    #|  id:   int64
    #|  name: string
    #|}
    #|
    #|type CreateUserReq {
    #|  name: string `json:"name"`
    #|}
    #|
    #|service greet {
    #|  get  /ping        ping         "health check"
    #|  get  /users/:id   get_user
    #|  post /users       create_user  "create a user"
    #|}
  let spec = @moonctl.parse(source)
  println(
    "parsed service \{spec.service}: \{spec.routes.length()} routes, \{spec.types.length()} types\n",
  )
  try {
    let scaffold = @moonctl.generate(spec)
    println("==== generate(spec) -> moonapi scaffold ====\n")
    println(scaffold)
  } catch {
    _ => println("mctl: codegen failed")
  }
  let doc = @moonctl.openapi_document(spec, version=OpenApi31, title="greet").stringify(
    indent=2,
  )
  println(
    "==== openapi_document(spec, version=OpenApi31) -> OpenAPI 3.1 ====\n",
  )
  println(doc)
}
