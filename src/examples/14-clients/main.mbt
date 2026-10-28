///|
/// One spec, four clients and a Markdown reference — what `mctl api ts|dart|kt|java`
/// and `mctl api doc` generate, without touching the disk.
///
/// The spec below is small but not trivial: a body route, a path parameter, a query
/// parameter, a header, an optional field and a nested type. The four clients are
/// generated from it, and the lines printed are the ones each language spells its
/// own way: the call, the model and the error.
///
///     moon run src/examples/14-clients
#coverage.skip
fn main raise {
  let source =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @doc "create a user"
    #|  @handler createUser
    #|  post /users (CreateReq) returns (User)
    #|
    #|  @handler getUser
    #|  get /users/:id (GetReq) returns (User)
    #|}
    #|
    #|type GetReq {
    #|  id: int64 `path:"id"`
    #|  verbose: bool `form:"verbose,optional"`
    #|}
    #|
    #|type CreateReq {
    #|  name: string `json:"name"`
    #|  owner: User `json:"owner"`
    #|}
    #|
    #|type User {
    #|  id: int64 `json:"id"`
    #|  name: string `json:"name"`
    #|  nickname: string `json:"nickname,optional"`
    #|}
  let spec = @moonctl.parse(source)
  // formatting is idempotent: the canonical form of the canonical form is itself
  let formatted = @moonctl.format(source)
  println(
    "api format is stable: " +
    (formatted == @moonctl.format(formatted)).to_string(),
  )
  // and a valid spec has nothing to report
  println(
    "api validate: " +
    @moonctl.validate_source(source).length().to_string() +
    " finding(s)",
  )
  println("")
  for
    (lang, file) in [
      (@moonctl.Lang::TypeScript, "greet_client.ts"),
      (@moonctl.Lang::Dart, "greet_client.dart"),
      (@moonctl.Lang::Kotlin, "greet_client.kt"),
      (@moonctl.Lang::Java, "GreetClient.java"),
    ] {
    let (name, text) = @moonctl.client_file(spec, lang)
    println(
      lang.label() +
      " → " +
      name +
      " (" +
      text.length().to_string() +
      " bytes)",
    )
    println(
      "  " + name + " is named as expected: " + (name == file).to_string(),
    )
  }
  println("")
  let doc = @moonctl.generate_markdown(spec)
  println("Markdown reference: " + doc.length().to_string() + " bytes")
  println("")
  // the route table is the part of the reference a reader comes for
  let mut header = 0
  while header < doc.length() && doc[header] != '#' {
    header = header + 1
  }
  println(doc[if header < doc.length() { header } else { 0 }:].to_owned())
}
