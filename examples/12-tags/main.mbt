///|
/// Struct tags: where a field binds from, what it is called there, and what it has
/// to look like. A `type` field carries its raw back-tick tag verbatim in
/// `Field::tag`; `Field::bind` reads whether the value comes out of the request body
/// (`json:`), the query string (`form:`), a URL segment (`path:`) or a header
/// (`header:`), `Field::json_name` the name it arrives under there, and
/// `Field::optional` / `default_` / `options` / `range` the constraints that follow
/// that name. `openapi_document` documents each of them where it belongs — a `form:`
/// field as a query parameter, a body field as a schema property with its `default`,
/// `enum` and bounds — and the generated `types.mbt` carries the `with_defaults` and
/// `check` that enforce the same rules at run time.
///
///     moon run examples/12-tags
#coverage.skip
fn main raise {
  let source =
    #|type ListAccounts {
    #|  region:    string `path:"region"`
    #|  page:      int    `form:"page,default=1,range=[1:100]"`
    #|  sort:      string `form:"sort,options=asc|desc"`
    #|  trace:     string `header:"X-Trace"`
    #|}
    #|
    #|type Account {
    #|  id:        int64  `json:"account_id"`
    #|  handle:    string `json:"handle"`
    #|  email:     string `json:"email,omitempty"`
    #|  api_token: string `json:"apiToken,optional"`
    #|  note:      string
    #|}
    #|
    #|service accounts {
    #|  @handler list_accounts
    #|  get /regions/:region/accounts (ListAccounts) returns (Account)
    #|}
  let spec = @moonctl.parse(source)
  for t in spec.types {
    println("type \{t.name}:")
    for f in t.fields {
      let where_ = match f.bind() {
        Body => "body"
        Query => "query"
        Path => "path"
        Header => "header"
      }
      let extra = (if f.optional() { " optional" } else { "" }) +
        (match f.default_() {
          Some(d) => " default=" + d
          None => ""
        })
      println(
        "  \{f.name} : \{f.type_}  ->  \{where_} \"\{f.json_name()}\"\{extra}",
      )
    }
  }
  println("\n==== the checks those tags generate ====\n")
  println(@moonctl.generate(spec))
  println("\n==== openapi_document(spec) ====\n")
  println(
    @moonctl.openapi_document(spec, version=OpenApi31).stringify(indent=2),
  )
}
