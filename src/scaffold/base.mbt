// What every service tree shares, whatever it serves: the module, its entry
// point, the configuration the entry point reads and the context handed to the
// author's code.

///|
/// The shared part of a service tree for module `module_`. `deps` are the
/// libraries the module imports besides `moonbitlang/async`, and `imports` and
/// `main` make up the entry point.
fn base_tree(
  module_ : String,
  st : @style.Style,
  dir : String,
  deps~ : Array[String],
  imports~ : Array[(String, String)],
  main~ : String,
) -> Array[TreeFile] {
  let file = st.format(module_)
  let config_pkg = module_ + "/internal/config"
  let svc_pkg = module_ + "/internal/svc"
  let mod_deps = deps.copy()
  mod_deps.push("moonbitlang/async")
  let main_imports = imports.copy()
  main_imports.push(("moonbitlang/async", ""))
  main_imports.push((config_pkg, ""))
  main_imports.push((svc_pkg, ""))
  let config =
    #|///|
    #|/// What the %svc service reads out of `etc/%file.yaml`.
    #|pub(all) struct Config {
    #|  host : String
    #|  port : Int32
    #|}
    #|
    #|///|
    #|/// The configuration `etc/%file.yaml` ships with.
    #|pub fn Config::new(host~ : String = "0.0.0.0", port~ : Int32 = %port) -> Config {
    #|  { host, port }
    #|}
  let context =
    #|///|
    #|/// What the author's code is given besides its input: the loaded configuration,
    #|/// and whatever else the service depends on. Add those here.
    #|pub(all) struct ServiceContext {
    #|  config : @config.Config
    #|}
    #|
    #|///|
    #|pub fn ServiceContext::new(config : @config.Config) -> ServiceContext {
    #|  { config, }
    #|}
  let fill = (s : String) => {
    s
    .replace_all(old="%svc", new=module_)
    .replace_all(old="%file", new=file)
    .replace_all(old="%port", new=port.to_string()) +
    "\n"
  }
  [
    {
      path: at(dir, "moon.mod"),
      content: mod_file(module_, mod_deps),
      regen: Once,
    },
    {
      path: at(dir, "moon.pkg"),
      content: pkg_file(main_imports, main_=true),
      regen: Once,
    },
    { path: at(dir, file + ".mbt"), content: main, regen: Once, },
    {
      path: at(dir, "etc/" + file + ".yaml"),
      content: "name: " +
      module_ +
      "\nhost: 0.0.0.0\nport: " +
      port.to_string() +
      "\n",
      regen: Once,
    },
    {
      path: at(dir, "internal/config/moon.pkg"),
      content: pkg_file([]),
      regen: Once,
    },
    {
      path: at(dir, "internal/config/" + st.format("config") + ".mbt"),
      content: fill(config),
      regen: Once,
    },
    {
      path: at(dir, "internal/svc/moon.pkg"),
      content: pkg_file([(config_pkg, "")]),
      regen: Once,
    },
    {
      path: at(dir, "internal/svc/" + st.format("service_context") + ".mbt"),
      content: fill(context),
      regen: Once,
    },
  ]
}

///|
/// The entry point of a service that serves an ASGI application `app` built from
/// `cfg` and `svc`, announcing itself as serving `what`.
fn asgi_main(module_ : String, what : String, app : String) -> String {
  let src =
    #|///|
    #|/// The %svc service: read the configuration, build the context its code shares
    #|/// and serve %what on mooncat.
    #|async fn main {
    #|  let cfg = @config.Config::new()
    #|  let svc = @svc.ServiceContext::new(cfg)
    #|  let app = %app
    #|  println("%svc serving %what on " + cfg.host + ":" + cfg.port.to_string())
    #|  @mooncat.serve(app, host=cfg.host, port=cfg.port)
    #|}
  src
  .replace_all(old="%svc", new=module_)
  .replace_all(old="%what", new=what)
  .replace_all(old="%app", new=app) +
  "\n"
}
