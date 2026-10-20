// Multi-file specs. goctl lets a `.api` pull in others — `import "user.api"`, or a
// grouped `import ( … )` — and every path is relative to the file that wrote it, so
// resolving one takes both. Reading files is not this package's job (it stays pure
// and all-backend), so the split is: `deps` tells a caller which files a source
// needs, and `parse_all` merges the sources it collected into one `Spec` — imports
// first, in the order they were declared.

///|
/// Whether `c` separates path segments. A spec path can arrive from a Windows
/// shell, so both spellings count.
fn is_sep(c : UInt16) -> Bool {
  c == '/' || c == '\\'
}

///|
/// The directory `p` lives in, without its trailing separator; "" when `p` names a
/// file in the current directory.
fn dir_of(p : String) -> String {
  let mut cut = -1
  for i = 0; i < p.length(); i = i + 1 {
    if is_sep(p[i]) {
      cut = i
    }
  }
  if cut < 0 {
    ""
  } else {
    p[0:cut].to_owned()
  }
}

///|
/// Whether `p` names a location by itself rather than relative to something.
fn is_absolute(p : String) -> Bool {
  if p.length() == 0 {
    return false
  }
  if is_sep(p[0]) {
    return true
  }
  p.length() >= 2 && p[1] == ':'
}

///|
/// `p` with its `.` and `..` segments folded away and `/` as the separator. A `..`
/// that climbs past the start is kept, since dropping it would quietly change which
/// file is meant.
fn normalize(p : String) -> String {
  let out : Array[String] = []
  let mut seg = ""
  let lead = if p.length() > 0 && is_sep(p[0]) { "/" } else { "" }
  for i = 0; i <= p.length(); i = i + 1 {
    if i == p.length() || is_sep(p[i]) {
      if seg == ".." && out.length() > 0 && out[out.length() - 1] != ".." {
        out.pop() |> ignore
      } else if seg != "." && seg != "" {
        out.push(seg)
      }
      seg = ""
    } else {
      seg = seg + p[i:i + 1].to_owned()
    }
  }
  let mut joined = ""
  for i = 0; i < out.length(); i = i + 1 {
    joined = if i == 0 { out[i] } else { joined + "/" + out[i] }
  }
  lead + joined
}

///|
/// An `import` path resolved against the file that declared it: taken relative to
/// that file's directory, with `.`/`..` folded away. An already-absolute path is
/// left where it points.
pub fn resolve_import(from : String, path : String) -> String {
  if is_absolute(path) {
    return normalize(path)
  }
  let dir = dir_of(from)
  normalize(if dir == "" { path } else { dir + "/" + path })
}

///|
/// The files `source` imports, each resolved against `from` — the path `source`
/// itself was read from. A caller that can read files walks a multi-file spec with
/// this: read a file, follow its `deps`, and hand everything it collected to
/// `parse_all`.
pub fn deps(source : String, from~ : String = "") -> Array[String] {
  let out : Array[String] = []
  for raw in parse_lenient(source).imports {
    out.push(resolve_import(from, raw))
  }
  out
}

///|
/// One file of the import graph, scanned.
priv struct Scan {
  path : String
  spec : Spec
  issues : Array[(Int32, String)]
}

///|
/// Scan `source` and everything it imports, depth-first and each file once, so an
/// imported file lands in `out` before the file that imported it.
fn walk(
  path : String,
  source : String,
  files : Map[String, String],
  seen : Map[String, Bool],
  out : Array[Scan],
) -> Unit raise SpecError {
  seen[path] = true
  let (spec, issues) = read(source)
  for raw in spec.imports {
    let next = resolve_import(path, raw)
    if seen.contains(next) {
      continue
    }
    match files.get(next) {
      Some(src) => walk(next, src, files, seen, out)
      None => raise Missing(file=path, path=raw)
    }
  }
  out.push({ path, spec, issues, })
}

///|
/// Parse `source` — the spec at `from` — together with everything it imports, taken
/// from `files` (a map from resolved path to source, the shape `deps` resolves to).
/// What the imports describe is merged in first, in the order they were declared,
/// then the importing file's own: types, routes and `@server` groups all end up in
/// one `Spec`. A file is scanned once however many times it is imported, so a cycle
/// terminates.
///
/// The service name is the last one declared, so the importing file's own `service`
/// block wins and a spec that does nothing but import still takes the name from what
/// it imported.
///
/// An `import` naming a file that is not in `files` raises `Missing`; a file that
/// does not parse raises its first complaint the way `parse` does, with the file it
/// came from named alongside the line.
pub fn parse_all(
  source : String,
  files : Map[String, String],
  from~ : String = "",
) -> Spec raise SpecError {
  let units : Array[Scan] = []
  walk(from, source, files, Map([]), units)
  for u in units {
    if u.issues.length() > 0 {
      let mut first = u.issues[0]
      for it in u.issues {
        if it.0 < first.0 {
          first = it
        }
      }
      let msg = if u.path == from { first.1 } else { u.path + ": " + first.1 }
      raise Syntax(line=first.0, msg~)
    }
  }
  let mut service = "app"
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let info : Array[(String, String)] = []
  let groups : Array[Group] = []
  let imports : Array[String] = []
  for u in units {
    if u.spec.service != "app" {
      service = u.spec.service
    }
    for r in u.spec.routes {
      routes.push(r)
    }
    for t in u.spec.types {
      types.push(t)
    }
    for kv in u.spec.info {
      info.push(kv)
    }
    for g in u.spec.groups {
      groups.push(g)
    }
    if u.path != from {
      imports.push(u.path)
    }
  }
  { service, routes, types, info, groups, imports, }
}
