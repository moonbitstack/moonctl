///|
/// A multi-file spec, a naming style, and the layered project tree — the three
/// things that separate `mctl gen api` from a single generated file. The entry spec
/// imports `user.api`, so its type and its grouped route are merged in; the tree is
/// then named in `go_zero` and written out; and the second pass shows what a
/// regeneration would actually touch once the first one is on disk.
///
///     moon run src/examples/13-tree
#coverage.skip
fn main raise {
  let files : Map[String, String] = Map([
    (
      "spec/user.api",
      (
        #|type LoginReq {
        #|  name: string `json:"name"`
        #|}
        #|
        #|@server(group: user, prefix: /api/v1, middleware: Log)
        #|service greet {
        #|  @doc "log a user in"
        #|  @handler login
        #|  post /login (LoginReq)
        #|}
      ),
    ),
  ])
  let source =
    #|import "user.api"
    #|
    #|service greet {
    #|  @handler get_one
    #|  get /one
    #|}
  println("==== imports ====\n")
  for dep in @moonctl.deps(source, from="spec/greet.api") {
    println("  spec/greet.api -> \{dep}")
  }
  let spec = @moonctl.parse_all(source, files, from="spec/greet.api")
  println(
    "\nmerged: \{spec.types.length()} type(s), \{spec.routes.length()} route(s)",
  )
  for r in spec.routes {
    println("  \{r.verb} \{r.path} -> \{r.handler}")
  }
  println("\n==== style ====\n")
  for template in ["gozero", "goZero", "go_zero", "Go#zero"] {
    println(
      "  \{template} -> \{@moonctl.Style::parse(template).format("welcome_to_go_zero")}",
    )
  }
  println("\n==== tree (--style go_zero) ====\n")
  let tree = @moonctl.generate_tree(
    spec,
    style=@moonctl.Style::parse("go_zero"),
  )
  for f in tree {
    println("  \{f.path}")
  }
  println("\n==== the second run ====\n")
  let written : Map[String, Bool] = Map([])
  for f in @moonctl.tree_plan(tree, _ => false) {
    written[f.path] = true
  }
  println(
    "first run wrote \{written.length()} file(s); running again would write:",
  )
  for f in @moonctl.tree_plan(tree, p => written.contains(p)) {
    println("  \{f.path}")
  }
  println(
    "\neverything else is yours once it exists — handler and logic bodies included.",
  )
}
