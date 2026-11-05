// What mctl wrote, formatted.
//
// A generated project is meant to be read and edited by a person, so it has to be
// in the shape `moon fmt` leaves code in: wrapping a call across lines, putting the
// trailing comma in a struct literal, collapsing an empty block. Reproducing those
// decisions in the generator would mean writing a second formatter and keeping the
// two in agreement; instead mctl runs the project's own formatter over the packages
// it just wrote, the way a Go tool runs `gofmt` over what it emits.
//
// The formatter is invoked only where a `moon.mod` exists — a flat single-file
// generation has no module to format in — and a failure is reported, never fatal:
// the files are written and correct either way.

///|
/// The directories of `files` that hold MoonBit source, in the order they first
/// appear and each once. A `.mbt` file makes its directory a package; `moon.pkg` is
/// formatted along with the package it belongs to, so it needs no entry of its own.
fn source_dirs(files : Array[@moonctl.GenFile]) -> Array[String] {
  let out : Array[String] = []
  for f in files {
    if @text.ends_with(f.path, ".mbt") == false {
      continue
    }
    let cut = last_index_of(f.path, '/')
    let dir = if cut < 0 { "." } else { f.path[0:cut].to_owned() }
    if out.contains(dir) == false {
      out.push(dir)
    }
  }
  out
}

///|
/// The module root among `files`: the directory of the `moon.mod` they include, or
/// "" when none was written — a generation into a flat file, or the docker and kube
/// snippets, which belong to no module of their own.
fn module_root(files : Array[@moonctl.GenFile]) -> String {
  for f in files {
    if f.path == "moon.mod" {
      return "."
    }
    if @text.ends_with(f.path, "/moon.mod") {
      return f.path[0:f.path.length() - "/moon.mod".length()].to_owned()
    }
  }
  ""
}

///|
/// Format the packages among `files` — the ones mctl just wrote — with `moon fmt`,
/// run at the module `root`. Nothing happens when the files carry no module of their
/// own: there is nothing to format them as part of.
pub async fn format_written(
  root : String,
  files : Array[@moonctl.GenFile],
) -> Unit {
  if root == "" || files.length() == 0 {
    return
  }
  let dirs = source_dirs(files)
  if dirs.length() == 0 {
    return
  }
  let argv : Array[String] = ["fmt"]
  for d in dirs {
    // `moon fmt` takes paths relative to where it runs, so a package is named
    // without the module directory in front of it; the module's own root package is
    // `.`.
    if root == "." || d == root {
      argv.push(if d == root { "." } else { d })
    } else {
      argv.push(d[root.length() + 1:].to_owned())
    }
  }
  let (code, _out, err) = @process.collect_output("moon", argv, cwd=root) catch {
    e => {
      println("mctl: could not run moon fmt: " + e.to_string())
      return
    }
  }
  if code != 0 {
    println("mctl: moon fmt left what was written unformatted: " + err.text())
  }
}
