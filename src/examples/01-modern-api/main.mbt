///|
/// The modern goctl `.api` dialect: an `info (...)` block, `@doc`/`@handler`
/// annotations, and typed `verb /path (Req) returns (Resp)` routes — as opposed
/// to the legacy inline `verb /path handler "summary"` form in `00-greet`. `parse`
/// fills each route's `req`/`resp` from the parentheses and its `handler`/`summary`
/// from the preceding annotations; `generate` emits the moonapi scaffold either way.
///
///     moon run src/examples/01-modern-api
#coverage.skip
fn main raise {
  let source =
    #|info (
    #|  title:   "user service"
    #|  desc:    "the modern goctl .api dialect"
    #|  version: "1.2.0"
    #|)
    #|
    #|type LoginReq {
    #|  name:     string `json:"name"`
    #|  password: string `json:"password"`
    #|}
    #|
    #|type LoginResp {
    #|  token: string `json:"token"`
    #|}
    #|
    #|type GetUserReq {
    #|  id: int64 `path:"id"`
    #|}
    #|
    #|type User {
    #|  id:   int64  `json:"id"`
    #|  name: string `json:"name"`
    #|}
    #|
    #|service user {
    #|  @doc "authenticate a user"
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|
    #|  @doc "fetch one user by id"
    #|  @handler get_user
    #|  get /users/:id (GetUserReq) returns (User)
    #|}
  let spec = @moonctl.parse(source)
  println("service \{spec.service}, \{spec.info.length()} info entries:")
  for kv in spec.info {
    println("  \{kv.0} = \{kv.1}")
  }
  println("")
  for r in spec.routes {
    println(
      "route \{r.verb} \{r.path} -> \{r.handler}  req=(\{r.req}) resp=(\{r.resp}) doc=\"\{r.summary}\"",
    )
  }
  println("\n==== generate(spec) -> moonapi scaffold ====\n")
  println(@moonctl.generate(spec)) catch {
    _ => println("mctl: codegen failed")
  }
}
