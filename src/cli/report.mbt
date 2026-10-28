// `mctl env` and `mctl bug` — the two commands that answer "what is this machine
// doing?" `env` prints what mctl resolved and where each value came from; `bug`
// prints the report a maintainer needs before they can reproduce anything.
//
// Both take the values as rows the caller collected, so the library formats and the
// binary reads the machine.

///|
/// `mctl env`: one line per setting, then a hint at what to change. `rows` pairs a
/// setting with its value and, in parentheses, where it came from.
pub fn env_report(version : String, rows : Array[(String, String)]) -> String {
  let out : Array[String] = []
  out.push("mctl " + version)
  out.push("")
  let width = 24
  for row in rows {
    let mut name = row.0
    while name.length() < width {
      name = name + " "
    }
    out.push("  " + name + row.1)
  }
  out.push("")
  out.push("Configuration comes from, in order: --home/--remote/--branch,")
  out.push(
    "then the mctl config file, then the defaults. `mctl config list` shows the file.",
  )
  @text.join_lines(out)
}

///|
/// `mctl bug`: a report with the environment filled in and the questions a
/// maintainer would otherwise have to ask. `title` may be empty, in which case the
/// report asks for one.
pub fn bug_report(
  title : String,
  version : String,
  rows : Array[(String, String)],
) -> String {
  let out : Array[String] = []
  out.push(
    "<!-- Paste this into a new issue: https://github.com/moonbitstack/moonctl/issues -->",
  )
  out.push("")
  out.push("# " + (if title == "" { "mctl: <what went wrong>" } else { title }))
  out.push("")
  out.push("## What happened")
  out.push("")
  out.push(
    "<!-- the command you ran, and what it printed; a failing spec is the most useful thing to attach -->",
  )
  out.push("")
  out.push("```console")
  out.push("$ mctl …")
  out.push("```")
  out.push("")
  out.push("## What you expected")
  out.push("")
  out.push("## Environment")
  out.push("")
  out.push("| Setting | Value |")
  out.push("| --- | --- |")
  out.push("| mctl | " + version + " |")
  for row in rows {
    out.push("| " + row.0 + " | " + row.1 + " |")
  }
  out.push("")
  out.push("## Anything else")
  out.push("")
  out.push(
    "<!-- a minimal .api or .proto that shows it, a workaround, a guess -->",
  )
  @text.join_lines(out)
}
