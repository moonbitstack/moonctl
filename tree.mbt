// The layered project tree, and what a second run of it is allowed to touch.
//
// goctl does not write one file: it writes `etc/<svc>.yaml`, `internal/config`,
// `internal/svc`, `internal/types`, `internal/handler` (routes plus one file per
// handler, under the group's own directory when the route is grouped),
// `internal/logic`, `internal/middleware` and the service's entry point. This is the
// same tree in MoonBit, one package per directory.
//
// The second run is the point of it. goctl regenerates only the two machine-owned
// files — the routes and the types — and skips every file that is already on disk,
// because those are where the author's code lives. Each file here therefore says
// which it is, and `tree_plan` is what turns a tree plus "does this exist?" into the
// files to actually write.

///|
/// Whether a regeneration may replace a file that is already on disk. `Always` is
/// for what moonctl owns — the routes and the types, which must follow the spec —
/// and `Once` for what it only seeds: handlers, logic, configuration, manifests.
pub(all) enum Regen {
  Always
  Once
} derive(Eq)

///|
pub extend Regen with Eq::{equal, not_equal}

///|
/// One file of a generated project tree: where it goes, what is in it, and whether
/// regenerating the tree is allowed to overwrite it.
pub(all) struct TreeFile {
  path : String
  content : String
  regen : Regen
}

///|
/// `rest` under `dir`, or `rest` alone when `dir` is empty.
fn at(dir : String, rest : String) -> String {
  if dir == "" {
    rest
  } else {
    dir + "/" + rest
  }
}

///|
/// `xs` with later repeats dropped, order kept.
fn uniq(xs : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for x in xs {
    let mut seen = false
    for y in out {
      if y == x {
        seen = true
      }
    }
    if seen == false {
      out.push(x)
    }
  }
  out
}

///|
/// The directory a route's handler and logic live in — its group, spelled in the
/// style — or "" for a route declared outside any `@server` block.
fn route_dir(r : Route, style : Style) -> String {
  match r.group {
    Some(g) if g.name != "" => style.format(g.name)
    _ => ""
  }
}

///|
/// Generate the layered project tree goctl writes, in MoonBit: the service entry
/// point and its `moon.mod`, `etc/<service>.yaml`, `internal/config`,
/// `internal/svc`, `internal/types`, `internal/handler` (the generated routes plus a
/// stub per handler, under `internal/handler/<group>/` for a grouped route),
/// `internal/logic`, `internal/middleware` for every middleware an `@server` block
/// named, and a `moon.pkg` for each of those packages.
///
/// `style` (default `gozero`) names the files and the handler, logic and middleware
/// entry points inside them. Names the spec itself chose — the `type` blocks and
/// their fields — are left as written, since a MoonBit type name has to keep its
/// capital. `dir` puts the whole tree under a directory.
///
/// Each file says whether a regeneration may overwrite it; hand the result to
/// `tree_plan` to apply that.
pub fn generate_tree(
  spec : Spec,
  style? : Style,
  dir? : String = "",
) -> Array[TreeFile] {
  let st = match style {
    Some(s) => s
    None => Style::gozero()
  }
  let out : Array[TreeFile] = []
  let mod_ = spec.service
  let svc_file = st.format(spec.service)
  let config_pkg = mod_ + "/internal/config"
  let svc_pkg = mod_ + "/internal/svc"
  let handler_pkg = mod_ + "/internal/handler"
  let logic_pkg = mod_ + "/internal/logic"
  let api = ("moonbitstack/moonapi", "")
  let asgi = ("moonbitstack/moonasgi", "")

  // The module itself.
  out.push({
    path: at(dir, "moon.mod"),
    content: mod_file(mod_, ["moonbitstack/moonapi", "moonbitstack/moonasgi"]),
    regen: Once,
  })
  out.push({
    path: at(dir, "moon.pkg"),
    content: pkg_file(
      [api, (config_pkg, ""), (svc_pkg, ""), (handler_pkg, "")],
      main_=true,
    ),
    regen: Once,
  })
  out.push({
    path: at(dir, svc_file + ".mbt"),
    content: "///|\n/// The " +
    spec.service +
    " service: read the configuration, build the context the handlers share, and\n/// register every route on a fresh app. What comes back is a moonasgi application —\n/// serve it with whichever server you run.\nfn main {\n  let cfg = @config.Config::new()\n  println(\"" +
    spec.service +
    " configured for \" + cfg.host + \":\" + cfg.port.to_string())\n  @handler.register_handlers(@moonapi.App::new(), @svc.ServiceContext::new(cfg))\n  |> ignore\n}\n",
    regen: Once,
  })

  // etc/<service>.yaml — the configuration the entry point reads.
  out.push({
    path: at(dir, "etc/" + svc_file + ".yaml"),
    content: "name: " +
    spec.service +
    "\nhost: 0.0.0.0\nport: " +
    port.to_string() +
    "\n",
    regen: Once,
  })

  // internal/config
  out.push({
    path: at(dir, "internal/config/moon.pkg"),
    content: pkg_file([]),
    regen: Once,
  })
  out.push({
    path: at(dir, "internal/config/" + st.format("config") + ".mbt"),
    content: "///|\n/// What the " +
    spec.service +
    " service reads out of `etc/" +
    svc_file +
    ".yaml`.\npub(all) struct Config {\n  host : String\n  port : Int\n}\n\n///|\n/// The configuration `etc/" +
    svc_file +
    ".yaml` ships with.\npub fn Config::new(host? : String = \"0.0.0.0\", port? : Int = " +
    port.to_string() +
    ") -> Config {\n  { host, port }\n}\n",
    regen: Once,
  })

  // internal/svc
  out.push({
    path: at(dir, "internal/svc/moon.pkg"),
    content: pkg_file([(config_pkg, "")]),
    regen: Once,
  })
  out.push({
    path: at(dir, "internal/svc/" + st.format("service_context") + ".mbt"),
    content: "///|\n/// What every handler is given besides its request: the loaded configuration, and\n/// whatever else the service depends on — add those here.\npub(all) struct ServiceContext {\n  config : @config.Config\n}\n\n///|\n/// Build the context the handlers share.\npub fn ServiceContext::new(config : @config.Config) -> ServiceContext {\n  { config, }\n}\n",
    regen: Once,
  })

  // internal/types — the spec's schemas, rewritten on every run.
  out.push({
    path: at(dir, "internal/types/moon.pkg"),
    content: pkg_file([]),
    regen: Once,
  })
  out.push({
    path: at(dir, "internal/types/" + st.format("types") + ".mbt"),
    content: "// Code generated by moonctl. DO NOT EDIT.\n\n" +
    render_structs(spec.types),
    regen: Always,
  })

  // internal/handler — the routes, rewritten on every run, and a stub per handler.
  let dirs : Array[String] = []
  for r in spec.routes {
    dirs.push(route_dir(r, st))
  }
  let group_dirs : Array[String] = []
  let mut ungrouped = false
  for d in uniq(dirs) {
    if d == "" {
      ungrouped = true
    } else {
      group_dirs.push(d)
    }
  }
  let routes_imports : Array[(String, String)] = [api, (svc_pkg, "")]
  if ungrouped {
    routes_imports.push(asgi)
    routes_imports.push((logic_pkg, "logic"))
  }
  for d in group_dirs {
    routes_imports.push((handler_pkg + "/" + d, d))
  }
  out.push({
    path: at(dir, "internal/handler/moon.pkg"),
    content: pkg_file(routes_imports),
    regen: Always,
  })
  out.push({
    path: at(dir, "internal/handler/" + st.format("routes") + ".mbt"),
    content: render_routes(spec, st),
    regen: Always,
  })
  for d in group_dirs {
    out.push({
      path: at(dir, "internal/handler/" + d + "/moon.pkg"),
      content: pkg_file([
        api,
        asgi,
        (svc_pkg, ""),
        (logic_pkg + "/" + d, "logic"),
      ]),
      regen: Once,
    })
  }
  for r in spec.routes {
    let d = route_dir(r, st)
    let name = st.format(r.handler + "_handler")
    out.push({
      path: at(dir, at("internal/handler", at(d, name + ".mbt"))),
      content: "///|\n/// `" +
      r.verb +
      " " +
      r.path +
      "` — the HTTP edge of the route: read the request, call\n/// the logic, write what comes back.\npub fn " +
      name +
      "(\n  svc : @svc.ServiceContext,\n  ctx : @moonapi.Context,\n) -> @moonasgi.Response {\n  @logic." +
      st.format(r.handler + "_logic") +
      "(svc, ctx)\n}\n",
      regen: Once,
    })
  }

  // internal/logic — one package per group, mirroring the handlers.
  let logic_dirs = if ungrouped { [""] } else { [] }
  for d in group_dirs {
    logic_dirs.push(d)
  }
  for d in logic_dirs {
    out.push({
      path: at(dir, at("internal/logic", at(d, "moon.pkg"))),
      content: pkg_file([api, asgi, (svc_pkg, "")]),
      regen: Once,
    })
  }
  for r in spec.routes {
    let d = route_dir(r, st)
    let name = st.format(r.handler + "_logic")
    out.push({
      path: at(dir, at("internal/logic", at(d, name + ".mbt"))),
      content: "///|\n/// `" +
      r.verb +
      " " +
      r.path +
      "`" +
      (if r.summary == "" { "" } else { " — " + r.summary }) +
      ". This is where the service does its work.\npub fn " +
      name +
      "(\n  _svc : @svc.ServiceContext,\n  _ctx : @moonapi.Context,\n) -> @moonasgi.Response {\n  @moonapi.text(200, " +
      quote("TODO: " + r.handler) +
      ")\n}\n",
      regen: Once,
    })
  }

  // internal/middleware — one per name any @server block asked for.
  let names : Array[String] = []
  for g in spec.groups {
    for m in g.middleware {
      names.push(m)
    }
  }
  let middleware = uniq(names)
  if middleware.length() > 0 {
    out.push({
      path: at(dir, "internal/middleware/moon.pkg"),
      content: pkg_file([api, asgi]),
      regen: Once,
    })
  }
  for m in middleware {
    let name = st.format(m + "_middleware")
    out.push({
      path: at(dir, "internal/middleware/" + name + ".mbt"),
      content: "///|\n/// The " +
      m +
      " middleware of the " +
      spec.service +
      " service: wrap the handler it is\n/// given and return the wrapper.\npub fn " +
      name +
      "(\n  next : (@moonapi.Context) -> @moonasgi.Response,\n) -> (@moonapi.Context) -> @moonasgi.Response {\n  next\n}\n",
      regen: Once,
    })
  }
  out
}

///|
/// `internal/handler/routes.mbt`: every route registered on the app, each one
/// calling into the handler package its group lives in. Regenerated on every run,
/// which is why nothing of the author's belongs in it.
fn render_routes(spec : Spec, st : Style) -> String {
  let svc = if spec.routes.length() == 0 { "_svc" } else { "svc" }
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n///|\n/// Register every route of the " +
    spec.service +
    " service on `app`.\npub fn register_handlers(\n  app : @moonapi.App,\n  " +
    svc +
    " : @svc.ServiceContext,\n) -> @moonapi.App {\n"
  let mut note = ""
  for r in spec.routes {
    let mark = match r.group {
      Some(g) => group_note(g)
      None => ""
    }
    if mark != note {
      out = out +
        (if mark == "" {
          "  // (ungrouped)\n"
        } else {
          "  // @server " + mark + "\n"
        })
      note = mark
    }
    let d = route_dir(r, st)
    let call = (if d == "" { "" } else { "@" + d + "." }) +
      st.format(r.handler + "_handler")
    let head = "  app." +
      r.verb +
      "(" +
      quote(r.path) +
      ", ctx => " +
      call +
      "(svc, ctx)"
    out = out +
      (if r.summary != "" {
        head + ", summary=" + quote(r.summary) + ")\n"
      } else {
        head + ")\n"
      })
  }
  out + "  app\n}\n"
}

///|
/// The files of `tree` a run should actually write, given a way to ask whether a
/// path is already on disk. A file moonctl owns (`Always` — the routes and the
/// types) is always written; anything else is written only when it is not there
/// yet, so a second run refreshes what follows the spec and leaves every handler and
/// logic body the author has since filled in exactly as it is.
pub fn tree_plan(
  tree : Array[TreeFile],
  exists : (String) -> Bool,
) -> Array[GenFile] {
  let out : Array[GenFile] = []
  for f in tree {
    if f.regen == Always || exists(f.path) == false {
      out.push({ path: f.path, content: f.content, })
    }
  }
  out
}
