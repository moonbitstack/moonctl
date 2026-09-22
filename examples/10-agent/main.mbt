///|
/// The `agent` generator — the moonbitstack suite's extension past goctl. Where
/// `generate` scaffolds a moonapi web tier and `generate_grpc` a moonrpc service,
/// `generate_agent` turns each `.api` route into a moonkoog `Tool` (its descriptor
/// advertises the operation, its `execute_raw` a stub) and assembles them into a
/// `build_agent` that wires the tools into an `AIAgent` named after the service.
/// The output compiles against `moonbitstack/moonkoog`; fill in each `execute_raw`.
///
///     moon run examples/10-agent
#coverage.skip
fn main raise {
  let source =
    #|service support {
    #|  get  /tickets/:id  get_ticket    "fetch a ticket"
    #|  post /tickets      open_ticket   "open a ticket"
    #|  post /tickets/:id/close close_ticket "close a ticket"
    #|}
  let spec = @moonctl.parse(source)
  println(
    "service \{spec.service}: \{spec.routes.length()} routes -> agent tools\n",
  )
  println("==== generate_agent(spec) -> moonkoog agent scaffold ====\n")
  println(@moonctl.generate_agent(spec))
}
