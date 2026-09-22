// The `moon.mod` and `moon.pkg` every generated project is written with, in the
// format `moon new` writes today. Both the scaffolds and the layered tree go
// through here, so the two cannot drift apart.

///|
/// The version of each library generated code imports.
///
/// These are the versions this repository's CI scaffolds a project against and
/// builds, so a generated project is promised to compile with them. A project that
/// wants a later release edits its own `moon.mod`.
pub let pins : Map[String, String] = {
  "moonbitstack/moonapi": "0.11.1",
  "moonbitstack/moonasgi": "0.10.0",
  "moonbitstack/moonrpc": "0.19.1",
  "moonbitstack/moonorm": "0.10.0",
  "moonbitstack/moondb": "0.2.0",
}

///|
/// A `moon.mod` for module `name`, importing each of `deps` at its pin.
fn mod_file(name : String, deps : Array[String]) -> String {
  let out = StringBuilder()
  out.write_string("name = " + quote(name) + "\n\nversion = \"0.1.0\"\n")
  if deps.length() > 0 {
    out.write_string("\nimport {\n")
    for dep in deps {
      guard pins.get(dep) is Some(version) else {
        abort(
          "moonctl generates an import of " + dep + " but has no pin for it",
        )
      }
      out.write_string("  " + quote(dep + "@" + version) + ",\n")
    }
    out.write_string("}\n")
  }
  out.to_string()
}

///|
/// A `moon.pkg` importing `entries`, each a `(path, alias)` pair where an empty
/// alias leaves the path's last segment as the name, and marked as the module's
/// native executable when `main_`.
fn pkg_file(entries : Array[(String, String)], main_? : Bool = false) -> String {
  let out = StringBuilder()
  if entries.length() > 0 {
    out.write_string("import {\n")
    for entry in entries {
      out.write_string("  " + quote(entry.0))
      if entry.1 != "" {
        out.write_string(" @" + entry.1)
      }
      out.write_string(",\n")
    }
    out.write_string("}\n")
  }
  if main_ {
    if entries.length() > 0 {
      out.write_char('\n')
    }
    out.write_string(
      "supported_targets = \"native\"\n\npkgtype(kind: \"executable\")\n",
    )
  }
  out.to_string()
}
