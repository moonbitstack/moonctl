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
  "moonbitstack/moonapi": "0.17.9",
  "moonbitstack/moonasgi": "0.10.6",
  "moonbitstack/mooncat": "0.19.5",
  "moonbitstack/moonmcp": "0.1.9",
  "moonbitstack/moongql": "0.10.9",
  "moonbitstack/moonrpc": "0.21.12",
  "moonbitstack/moonorm": "0.11.7",
  "moonbitstack/moondb": "0.2.6",
  "moonbitstack/moonhttp": "0.15.8",
  "moonbitlang/async": "0.22.5",
}

///|
/// A `moon.mod` for module `name`, importing each of `deps` at its pin.
fn mod_file(name : String, deps : Array[String]) -> String {
  let out = StringBuilder()
  out.write_string("name = " + @text.quote(name) + "\n\nversion = \"0.1.0\"\n")
  if deps.length() > 0 {
    out.write_string("\nimport {\n")
    for dep in deps {
      guard pins.get(dep) is Some(version) else {
        abort(
          "moonctl generates an import of " + dep + " but has no pin for it",
        )
      }
      out.write_string("  " + @text.quote(dep + "@" + version) + ",\n")
    }
    out.write_string("}\n")
  }
  out.to_string()
}

///|
/// A `moon.mod` for module `name` importing `deps`, with the `moonx` rules `rules`
/// names — the build step that turns annotations into code.
fn mod_file_with_rules(
  name : String,
  deps : Array[String],
  rules : Array[(String, String)],
) -> String {
  let mut out = mod_file(name, deps)
  for r in rules {
    out = out + "\n" + rule_line(r.0, r.1)
  }
  out
}

///|
/// The `moonx` command that runs one of a library's generators, for the `rule(...)`
/// that wires it into `moon.mod`.
pub fn generator_command(library : String, cmd : String) -> String {
  "moonx " +
  library +
  "/cmd/" +
  cmd +
  "@" +
  pins.get(library).unwrap() +
  " -C \\\"$mod_dir\\\" \\\"$input\\\" -o \\\"$output\\\""
}

///|
/// The `rule(...)` entry that wires a `moonx` generator into `moon.mod`, on one line
/// when it fits in the width `moon fmt` breaks at and one argument per line when it
/// does not — the two shapes the formatter leaves it in, so a generated `moon.mod`
/// never changes on the first format.
pub fn rule_line(name : String, command : String) -> String {
  let one = "rule(name: " +
    @text.quote(name) +
    ", command: " +
    @text.quote(command) +
    ")"
  if one.length() <= 80 {
    one + "\n"
  } else {
    "rule(\n  name: " +
    @text.quote(name) +
    ",\n  command: " +
    @text.quote(command) +
    ",\n)\n"
  }
}

///|
/// A `moon.pkg` importing `entries`, each a `(path, alias)` pair where an empty
/// alias leaves the path's last segment as the name, and marked as the module's
/// native executable when `main_`.
fn pkg_file(entries : Array[(String, String)], main_~ : Bool = false) -> String {
  let out = StringBuilder()
  if entries.length() > 0 {
    out.write_string("import {\n")
    for entry in entries {
      out.write_string("  " + @text.quote(entry.0))
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
