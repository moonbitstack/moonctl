// The plugin protocol, spoken the way goctl speaks it. goctl runs the plugin as
// `<bin> <args…>` and writes it one JSON object on stdin — `{Api, ApiFilePath,
// Style, Dir}`: the parsed spec, the file it came from, the `--style` template and
// the output directory. A plugin needs all four; the spec alone cannot tell it
// where to write or how to spell what it writes. The reply is a JSON list of
// `{path, content}` files on stdout, which mctl writes out. The wire shapes and
// their (de)serialisers live here, in pure all-backend code; only the subprocess
// spawn (in the `mctl` binary) is native.

///|
/// One file a plugin asks mctl to write: a destination `path` (relative to the
/// output directory) and its full `content`.
pub(all) struct GenFile {
  path : String
  content : String
}

///|
/// What a plugin is handed on stdin (← goctl's `plugin.Plugin`): the parsed spec
/// under `api`, the `.api` file it was read from, the `--style` naming template,
/// and the directory the generated tree goes under.
pub(all) struct Plugin {
  api : Spec
  api_file_path : String
  style : String
  dir : String
}

///|
/// Split a plugin invocation into the program to run and the arguments to run it
/// with, the way goctl reads its `-plugin` value: the first whitespace-separated
/// word is the executable, the rest are its argv. A quoted word keeps its spaces.
pub fn plugin_argv(invocation : String) -> (String, Array[String]) {
  let toks = tokens(invocation)
  if toks.length() == 0 {
    return ("", [])
  }
  let args : Array[String] = []
  for i = 1; i < toks.length(); i = i + 1 {
    args.push(toks[i])
  }
  (toks[0], args)
}

///|
/// A `Group` as JSON: the `@server` annotations under goctl's own key names, with
/// the group name under `name`.
fn group_to_json(g : Group) -> Json {
  let extra : Array[Json] = []
  for kv in g.extra {
    let m : Map[String, Json] = Map([
      ("name", Json(kv.0)),
      ("value", Json(kv.1)),
    ])
    extra.push(Json(m))
  }
  let m : Map[String, Json] = Map([
    ("name", Json(g.name)),
    ("prefix", Json(g.prefix)),
    ("jwt", Json(g.jwt)),
    ("middleware", Json(g.middleware)),
    ("maxBytes", Json(g.max_bytes.to_double())),
    ("timeout", Json(g.timeout)),
    ("signature", Json(g.signature)),
    ("extra", Json(extra)),
  ])
  Json(m)
}

///|
/// Serialise a `Spec` into the plugin request JSON. The shape mirrors the `Spec`
/// itself — `service`, `routes` (`verb`/`path`/`handler`/`summary`, plus the
/// `group` the route was declared under), `types` (`name` plus `fields` of
/// `name`/`type`) and `groups` — so a plugin in any language parses it with an
/// ordinary JSON reader. `type_` is written as `type`, the name a caller expects.
pub fn spec_to_json(spec : Spec) -> Json {
  let routes : Array[Json] = []
  for r in spec.routes {
    let m : Map[String, Json] = Map([
      ("verb", Json(r.verb)),
      ("path", Json(r.path)),
      ("handler", Json(r.handler)),
      ("summary", Json(r.summary)),
      ("req", Json(r.req)),
      ("resp", Json(r.resp)),
    ])
    match r.group {
      Some(g) => m["group"] = group_to_json(g)
      None => ()
    }
    routes.push(Json(m))
  }
  let types : Array[Json] = []
  for t in spec.types {
    let fields : Array[Json] = []
    for f in t.fields {
      let fm : Map[String, Json] = Map([
        ("name", Json(f.name)),
        ("type", Json(f.type_)),
        ("tag", Json(f.tag)),
      ])
      fields.push(Json(fm))
    }
    let tm : Map[String, Json] = Map([
      ("name", Json(t.name)),
      ("fields", Json(fields)),
      ("embeds", Json(t.embeds)),
    ])
    types.push(Json(tm))
  }
  let info : Array[Json] = []
  for kv in spec.info {
    let m : Map[String, Json] = Map([
      ("name", Json(kv.0)),
      ("value", Json(kv.1)),
    ])
    info.push(Json(m))
  }
  let groups : Array[Json] = []
  for g in spec.groups {
    groups.push(group_to_json(g))
  }
  let doc : Map[String, Json] = Map([
    ("service", Json(spec.service)),
    ("routes", Json(routes)),
    ("types", Json(types)),
    ("info", Json(info)),
    ("groups", Json(groups)),
  ])
  Json(doc)
}

///|
/// The plugin request as a two-space-indented JSON string, ready to write to the
/// plugin's stdin: goctl's four keys — the spec under `Api`, plus the file it was
/// read from, the `--style` template and the output directory, which is everything
/// a plugin needs to decide where its output goes and what to call it.
pub fn plugin_request(
  spec : Spec,
  api_file_path~ : String = "",
  style~ : String = "gozero",
  dir~ : String = "",
) -> String {
  let doc : Map[String, Json] = Map([
    ("Api", spec_to_json(spec)),
    ("ApiFilePath", Json(api_file_path)),
    ("Style", Json(style)),
    ("Dir", Json(dir)),
  ])
  Json(doc).stringify(indent=2)
}

///|
/// Read the request a plugin was handed on stdin. Missing members degrade to empty
/// rather than raising, so a hand-written request still parses.
pub fn plugin_from_json(j : Json) -> Plugin {
  let m = match j {
    Object(m) => m
    _ => Map([])
  }
  {
    api: spec_from_json(j),
    api_file_path: json_str(m, "ApiFilePath"),
    style: match json_str(m, "Style") {
      "" => "gozero"
      s => s
    },
    dir: json_str(m, "Dir"),
  }
}

///|
/// A `Group` read back from the request JSON, or `None` when the member is absent
/// or is not an object.
fn group_from_json(j : Json?) -> Group? {
  let m = match j {
    Some(Object(m)) => m
    _ => return None
  }
  let middleware : Array[String] = []
  match m.get("middleware") {
    Some(Array(a)) =>
      for it in a {
        match it {
          String(s) => middleware.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  let extra : Array[(String, String)] = []
  match m.get("extra") {
    Some(Array(a)) =>
      for it in a {
        match it {
          Object(em) =>
            extra.push((json_str(em, "name"), json_str(em, "value")))
          _ => ()
        }
      }
    _ => ()
  }
  let max_bytes = match m.get("maxBytes") {
    Some(Number(n, ..)) => n.to_int64()
    Some(String(s)) =>
      match to_i64(s) {
        Some(v) => v
        None => 0L
      }
    _ => 0L
  }
  let signature = match m.get("signature") {
    Some(True) => true
    _ => false
  }
  Some({
    name: json_str(m, "name"),
    prefix: json_str(m, "prefix"),
    jwt: json_str(m, "jwt"),
    middleware,
    max_bytes,
    timeout: json_str(m, "timeout"),
    signature,
    extra,
  })
}

///|
/// Reconstruct a `Spec` from the request JSON — the reader a plugin written in
/// MoonBit uses on its stdin. The whole request (`{Api, ApiFilePath, Style, Dir}`)
/// and a bare spec are both accepted, so a plugin that wants nothing but the routes
/// need not unwrap the envelope. Missing or mistyped members degrade to empty
/// rather than raising, so a partial request still parses.
pub fn spec_from_json(j : Json) -> Spec {
  let j = match j {
    Object(m) =>
      match m.get("Api") {
        Some(api) => api
        None => j
      }
    _ => j
  }
  let service = match j {
    Object(m) =>
      match m.get("service") {
        Some(String(s)) => s
        _ => "app"
      }
    _ => "app"
  }
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let info : Array[(String, String)] = []
  let groups : Array[Group] = []
  match j {
    Object(m) => {
      match m.get("groups") {
        Some(Array(arr)) =>
          for item in arr {
            match group_from_json(Some(item)) {
              Some(g) => groups.push(g)
              None => ()
            }
          }
        _ => ()
      }
      match m.get("routes") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(rm) =>
                routes.push({
                  verb: json_str(rm, "verb"),
                  path: json_str(rm, "path"),
                  handler: json_str(rm, "handler"),
                  summary: json_str(rm, "summary"),
                  req: json_str(rm, "req"),
                  resp: json_str(rm, "resp"),
                  group: group_from_json(rm.get("group")),
                })
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("types") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(tm) => {
                let fields : Array[Field] = []
                match tm.get("fields") {
                  Some(Array(fa)) =>
                    for f in fa {
                      match f {
                        Object(fm) =>
                          fields.push({
                            name: json_str(fm, "name"),
                            type_: json_str(fm, "type"),
                            tag: json_str(fm, "tag"),
                          })
                        _ => ()
                      }
                    }
                  _ => ()
                }
                let embeds : Array[String] = []
                match tm.get("embeds") {
                  Some(Array(ea)) =>
                    for e in ea {
                      match e {
                        String(s) => embeds.push(s)
                        _ => ()
                      }
                    }
                  _ => ()
                }
                types.push({ name: json_str(tm, "name"), fields, embeds, })
              }
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("info") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(im) =>
                info.push((json_str(im, "name"), json_str(im, "value")))
              _ => ()
            }
          }
        _ => ()
      }
    }
    _ => ()
  }
  // A plugin is handed a spec whose imports have already been merged in, so the
  // request carries no import list to read back.
  { service, routes, types, info, groups, imports: [], }
}

///|
/// Read a string member of a JSON object, or `""` if absent or non-string.
fn json_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Parse a plugin's stdout into the files to write. Two shapes are accepted: a bare
/// array `[{path, content}, …]`, or an object `{"files": [ … ]}` (goctl-style
/// envelope). An element missing `path` or `content` is skipped. The list preserves
/// the plugin's order.
pub fn parse_gen_files(j : Json) -> Array[GenFile] {
  let out : Array[GenFile] = []
  let arr = match j {
    Array(a) => a
    Object(m) =>
      match m.get("files") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  for item in arr {
    match item {
      Object(fm) => {
        let path = json_str(fm, "path")
        let content = json_str(fm, "content")
        if path != "" {
          out.push({ path, content, })
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Serialise a list of generated files into the plugin-reply JSON — the writer a
/// MoonBit plugin uses on its stdout. Emits the `{"files": [...]}` envelope.
pub fn gen_files_to_json(files : Array[GenFile]) -> Json {
  let arr : Array[Json] = []
  for f in files {
    let m : Map[String, Json] = Map([
      ("path", Json(f.path)),
      ("content", Json(f.content)),
    ])
    arr.push(Json(m))
  }
  let doc : Map[String, Json] = Map([("files", Json(arr))])
  Json(doc)
}
