///|
/// The sample spec the tree tests generate from: a grouped route with middleware,
/// an ungrouped one, and a type.
fn sample_spec() -> Spec raise SpecError {
  parse(
    (
      #|type LoginReq {
      #|  name: string
      #|}
      #|
      #|@server(group: user, prefix: /api/v1, middleware: Log)
      #|service greet {
      #|  @doc "log a user in"
      #|  @handler login
      #|  post /login (LoginReq)
      #|}
      #|
      #|service greet {
      #|  @handler get_one
      #|  get /one
      #|}
    ),
  )
}

///|
/// Every path of `tree`, newline-joined.
fn paths(tree : Array[TreeFile]) -> String {
  let mut out = ""
  for f in tree {
    out = if out == "" { f.path } else { out + "\n" + f.path }
  }
  out
}

///|
/// Every path of `files`, newline-joined.
fn gen_paths(files : Array[GenFile]) -> String {
  let mut out = ""
  for f in files {
    out = if out == "" { f.path } else { out + "\n" + f.path }
  }
  out
}

///|
/// The content of the file at `path`, or "" if the tree has no such file.
fn tree_at(tree : Array[TreeFile], path : String) -> String {
  for f in tree {
    if f.path == path {
      return f.content
    }
  }
  ""
}

///|
test "a generated tree lays the service out the way goctl does" {
  inspect(
    paths(generate_tree(sample_spec())),
    content=(
      #|moon.mod
      #|moon.pkg
      #|greet.mbt
      #|etc/greet.yaml
      #|internal/config/moon.pkg
      #|internal/config/config.mbt
      #|internal/svc/moon.pkg
      #|internal/svc/servicecontext.mbt
      #|internal/types/moon.pkg
      #|internal/types/types.mbt
      #|internal/handler/moon.pkg
      #|internal/handler/routes.mbt
      #|internal/handler/user/moon.pkg
      #|internal/handler/user/loginhandler.mbt
      #|internal/handler/getonehandler.mbt
      #|internal/logic/moon.pkg
      #|internal/logic/user/moon.pkg
      #|internal/logic/user/loginlogic.mbt
      #|internal/logic/getonelogic.mbt
      #|internal/middleware/moon.pkg
      #|internal/middleware/logmiddleware.mbt
    ),
  )
}

///|
test "a grouped route lives under its group, an ungrouped one beside the routes" {
  let tree = generate_tree(sample_spec(), dir="out")
  assert_eq(
    tree_at(tree, "out/internal/handler/user/loginhandler.mbt") != "",
    true,
  )
  assert_eq(tree_at(tree, "out/internal/handler/getonehandler.mbt") != "", true)
  let routes = tree_at(tree, "out/internal/handler/routes.mbt")
  // the grouped route is called through its own package, the ungrouped one directly
  assert_eq(
    contains(
      routes, "app.post(\"/api/v1/login\", ctx => @user.loginhandler(svc, ctx)",
    ),
    true,
  )
  assert_eq(
    contains(routes, "app.get(\"/one\", ctx => getonehandler(svc, ctx))"),
    true,
  )
  assert_eq(contains(routes, ", summary=\"log a user in\")"), true)
  assert_eq(contains(routes, "// @server group: user, prefix: /api/v1"), true)
  // and the handler package that routes.mbt calls into is imported under that name
  assert_eq(
    contains(
      tree_at(tree, "out/internal/handler/moon.pkg"),
      "\"greet/internal/handler/user\" @user,",
    ),
    true,
  )
}

///|
test "the types file carries the spec's schemas and the routes file the routes" {
  let tree = generate_tree(sample_spec())
  let types = tree_at(tree, "internal/types/types.mbt")
  assert_eq(contains(types, "pub(all) struct LoginReq {"), true)
  assert_eq(contains(types, "DO NOT EDIT"), true)
  assert_eq(
    contains(tree_at(tree, "internal/handler/routes.mbt"), "DO NOT EDIT"),
    true,
  )
  // what the author owns says nothing about being generated
  assert_eq(
    contains(
      tree_at(tree, "internal/handler/user/loginhandler.mbt"),
      "DO NOT EDIT",
    ),
    false,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/logic/user/loginlogic.mbt"),
      "pub fn loginlogic(",
    ),
    true,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/middleware/logmiddleware.mbt"),
      "pub fn logmiddleware(",
    ),
    true,
  )
}

///|
test "the tree is a module, with an entry point and a config to start from" {
  let tree = generate_tree(sample_spec())
  assert_eq(contains(tree_at(tree, "moon.mod"), "name = \"greet\""), true)
  assert_eq(
    contains(tree_at(tree, "moon.mod"), pinned("moonbitstack/moonapi")),
    true,
  )
  let main_pkg = tree_at(tree, "moon.pkg")
  assert_eq(contains(main_pkg, "pkgtype(kind: \"executable\")"), true)
  assert_eq(contains(main_pkg, "supported_targets = \"native\""), true)
  assert_eq(
    contains(tree_at(tree, "greet.mbt"), "@handler.register_handlers("),
    true,
  )
  // The family's default port, in the file and in the code that stands in for it.
  assert_eq(contains(tree_at(tree, "etc/greet.yaml"), "port: 12000"), true)
  assert_eq(
    contains(tree_at(tree, "internal/config/config.mbt"), "port? : Int = 12000"),
    true,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/config/config.mbt"),
      "pub(all) struct Config {",
    ),
    true,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/svc/servicecontext.mbt"),
      "pub fn ServiceContext::new(config : @config.Config)",
    ),
    true,
  )
}

///|
test "the style names every file and entry point the tree invents" {
  let tree = generate_tree(sample_spec(), style=Style::parse("go_zero"))
  assert_eq(tree_at(tree, "internal/svc/service_context.mbt") != "", true)
  assert_eq(
    tree_at(tree, "internal/handler/user/login_handler.mbt") != "",
    true,
  )
  assert_eq(tree_at(tree, "internal/handler/get_one_handler.mbt") != "", true)
  assert_eq(tree_at(tree, "internal/logic/user/login_logic.mbt") != "", true)
  assert_eq(tree_at(tree, "internal/middleware/log_middleware.mbt") != "", true)
  let routes = tree_at(tree, "internal/handler/routes.mbt")
  assert_eq(contains(routes, "@user.login_handler(svc, ctx)"), true)
  assert_eq(contains(routes, "get_one_handler(svc, ctx)"), true)
  assert_eq(
    contains(
      tree_at(tree, "internal/handler/user/login_handler.mbt"),
      "@logic.login_logic(svc, ctx)",
    ),
    true,
  )
  // the spec's own names keep their spelling — a MoonBit type needs its capital
  assert_eq(
    contains(
      tree_at(tree, "internal/types/types.mbt"),
      "pub(all) struct LoginReq {",
    ),
    true,
  )
}

///|
/// A spec whose service, group, handler and middleware names are all several words,
/// so a style that joins words differently shows up in every name the tree invents.
fn worded_spec() -> Spec raise SpecError {
  parse(
    (
      #|@server(group: order_admin, prefix: /api, middleware: audit_log)
      #|service user_center {
      #|  @handler list_orders
      #|  get /orders
      #|}
    ),
  )
}

///|
test "every name the tree invents is spelled in the style, not just the handlers" {
  inspect(
    paths(generate_tree(worded_spec(), style=Style::parse("GoZero"))),
    content=(
      #|moon.mod
      #|moon.pkg
      #|UserCenter.mbt
      #|etc/UserCenter.yaml
      #|internal/config/moon.pkg
      #|internal/config/Config.mbt
      #|internal/svc/moon.pkg
      #|internal/svc/ServiceContext.mbt
      #|internal/types/moon.pkg
      #|internal/types/Types.mbt
      #|internal/handler/moon.pkg
      #|internal/handler/Routes.mbt
      #|internal/handler/OrderAdmin/moon.pkg
      #|internal/handler/OrderAdmin/ListOrdersHandler.mbt
      #|internal/logic/OrderAdmin/moon.pkg
      #|internal/logic/OrderAdmin/ListOrdersLogic.mbt
      #|internal/middleware/moon.pkg
      #|internal/middleware/AuditLogMiddleware.mbt
    ),
  )
  // the group's package is imported under the same spelling the directory has
  let tree = generate_tree(worded_spec(), style=Style::parse("goZero"))
  assert_eq(
    contains(
      tree_at(tree, "internal/handler/moon.pkg"),
      "\"user_center/internal/handler/orderAdmin\" @orderAdmin,",
    ),
    true,
  )
  assert_eq(
    contains(
      tree_at(tree, "internal/handler/routes.mbt"),
      "@orderAdmin.listOrdersHandler(svc, ctx)",
    ),
    true,
  )
}

///|
test "a name two blocks ask for is written once, wherever the tree goes" {
  let spec = parse(
    (
      #|@server(group: user, middleware: Log,Trace)
      #|service greet {
      #|  @handler login
      #|  post /login
      #|
      #|  @handler logout
      #|  post /logout
      #|}
      #|
      #|@server(group: admin, middleware: Log)
      #|service greet {
      #|  @handler purge
      #|  delete /purge
      #|}
    ),
  )
  // two routes share one group package, two groups share one middleware, and every
  // path — the middleware's included — is under `dir`
  inspect(
    paths(generate_tree(spec, dir="out")),
    content=(
      #|out/moon.mod
      #|out/moon.pkg
      #|out/greet.mbt
      #|out/etc/greet.yaml
      #|out/internal/config/moon.pkg
      #|out/internal/config/config.mbt
      #|out/internal/svc/moon.pkg
      #|out/internal/svc/servicecontext.mbt
      #|out/internal/types/moon.pkg
      #|out/internal/types/types.mbt
      #|out/internal/handler/moon.pkg
      #|out/internal/handler/routes.mbt
      #|out/internal/handler/user/moon.pkg
      #|out/internal/handler/admin/moon.pkg
      #|out/internal/handler/user/loginhandler.mbt
      #|out/internal/handler/user/logouthandler.mbt
      #|out/internal/handler/admin/purgehandler.mbt
      #|out/internal/logic/user/moon.pkg
      #|out/internal/logic/admin/moon.pkg
      #|out/internal/logic/user/loginlogic.mbt
      #|out/internal/logic/user/logoutlogic.mbt
      #|out/internal/logic/admin/purgelogic.mbt
      #|out/internal/middleware/moon.pkg
      #|out/internal/middleware/logmiddleware.mbt
      #|out/internal/middleware/tracemiddleware.mbt
    ),
  )
}

///|
test "a service with no routes still gets a tree that compiles" {
  let tree = generate_tree(parse("service greet {\n}"))
  // nothing calls it, so the parameter is spelled as unused rather than warned on
  assert_eq(
    contains(
      tree_at(tree, "internal/handler/routes.mbt"),
      "_svc : @svc.ServiceContext",
    ),
    true,
  )
  // and a service that asked for no middleware gets no middleware package
  assert_eq(tree_at(tree, "internal/middleware/moon.pkg"), "")
}

///|
test "a second generation refreshes the routes and types and touches nothing else" {
  let first = tree_plan(generate_tree(sample_spec()), _ => false)
  // everything is written on the first run
  assert_eq(first.length(), 21)
  let on_disk : Map[String, Bool] = Map([])
  for f in first {
    on_disk[f.path] = true
  }
  inspect(
    gen_paths(tree_plan(generate_tree(sample_spec()), p => on_disk.contains(p))),
    content=(
      #|internal/types/types.mbt
      #|internal/handler/moon.pkg
      #|internal/handler/routes.mbt
    ),
  )
}

///|
test "a route added since the last run still gets its stub" {
  let on_disk : Map[String, Bool] = Map([])
  for f in tree_plan(generate_tree(sample_spec()), _ => false) {
    on_disk[f.path] = true
  }
  let grown = parse(
    (
      #|service greet {
      #|  @handler get_one
      #|  get /one
      #|
      #|  @handler ping
      #|  get /ping
      #|}
    ),
  )
  let plan = tree_plan(generate_tree(grown), p => on_disk.contains(p))
  let written = gen_paths(plan)
  // the new handler and its logic are seeded, the one already on disk is not
  assert_eq(contains(written, "internal/handler/pinghandler.mbt"), true)
  assert_eq(contains(written, "internal/logic/pinglogic.mbt"), true)
  assert_eq(contains(written, "internal/handler/getonehandler.mbt"), false)
  assert_eq(contains(written, "internal/logic/getonelogic.mbt"), false)
  // and the regenerated routes carry both
  for f in plan {
    if f.path == "internal/handler/routes.mbt" {
      assert_eq(contains(f.content, "getonehandler(svc, ctx)"), true)
      assert_eq(contains(f.content, "pinghandler(svc, ctx)"), true)
    }
  }
}
