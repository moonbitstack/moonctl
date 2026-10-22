///|
/// One `.api` spec, three OpenAPI dialects. `generate_doc` emits Swagger 2.0,
/// OpenAPI 3.0 and 3.1 from the same spec — the version drives how a typed request
/// body renders (2.0's `in: body` parameter vs 3.x's `requestBody`) and where the
/// `type` schemas land (`definitions` vs `components/schemas`). The `info (...)`
/// block feeds the document's `info` object, a `:id` path segment becomes a typed
/// path parameter, and `swagger_ui_stub` emits the HTML page that renders it all.
///
///     moon run examples/02-openapi-versions
#coverage.skip
fn main raise {
  let source =
    #|info (
    #|  title:   "catalog"
    #|  desc:    "product catalog service"
    #|  version: "2.0.0"
    #|)
    #|
    #|type Product {
    #|  id:    int64    `json:"id"`
    #|  name:  string   `json:"name"`
    #|  price: double   `json:"price"`
    #|  tags:  []string `json:"tags"`
    #|}
    #|
    #|type GetProductReq {
    #|  id: int64 `path:"id"`
    #|}
    #|
    #|type CreateProductReq {
    #|  name:  string `json:"name"`
    #|  price: double `json:"price"`
    #|}
    #|
    #|service catalog {
    #|  @doc "fetch one product"
    #|  @handler get_product
    #|  get /products/:id (GetProductReq) returns (Product)
    #|
    #|  @doc "create a product"
    #|  @handler create_product
    #|  post /products (CreateProductReq) returns (Product)
    #|}
  let spec = @moonctl.parse(source)
  let versions : Array[(String, @moonctl.DocVersion)] = [
    ("Swagger20", Swagger20),
    ("OpenApi30", OpenApi30),
    ("OpenApi31", OpenApi31),
  ]
  for v in versions {
    println("==== generate_doc(spec, version=\{v.0}) ====\n")
    println(@moonctl.generate_doc(spec, version=v.1))
    println("")
  }
  println("==== swagger_ui_stub(spec_url=\"/openapi.json\") ====\n")
  println(@moonctl.swagger_ui_stub(spec_url="/openapi.json", title="catalog"))
}
