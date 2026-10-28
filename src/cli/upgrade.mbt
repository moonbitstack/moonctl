// `mctl upgrade` — move the moonbitstack pins in a `moon.mod` to a release, without
// touching anything else in the file.
//
// A `moon.mod` pins its dependencies inside an `import { "org/name@1.2.3" }` block,
// one quoted string per line. The rewrite is line-oriented on purpose: comments,
// ordering and everything mctl does not own survive it untouched.

///|
/// The version `name` is pinned at in `mod`, or `None` when the file does not pin
/// it.
pub fn pinned_version(mod : String, name : String) -> String? {
  let head = "\"" + name + "@"
  for line in @text.split_char(mod, '\n') {
    let at = @text.index_of_str(line, head)
    if at < 0 {
      continue
    }
    let start = at + head.length()
    let rest = line[start:].to_owned()
    let close = @text.index_of_str(rest, "\"")
    if close > 0 {
      return Some(rest[0:close].to_owned())
    }
  }
  None
}

///|
/// The version strings of `mod`, as `(name, version)` pairs: every pin the file
/// carries, in order.
pub fn mod_pins(mod : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in @text.split_char(mod, '\n') {
    let open_at = @text.index_of_str(line, "\"")
    if open_at < 0 {
      continue
    }
    let rest = line[open_at + 1:].to_owned()
    let close = @text.index_of_str(rest, "\"")
    if close < 0 {
      continue
    }
    let pinned = rest[0:close].to_owned()
    let at = @text.index_of_str(pinned, "@")
    if at <= 0 {
      continue
    }
    out.push((pinned[0:at].to_owned(), pinned[at + 1:].to_owned()))
  }
  out
}

///|
/// `mod` with `name` pinned at `version`, or `mod` unchanged when it does not pin
/// that name. Returns the new text and the change it made, if any.
pub fn pin_module(
  mod : String,
  name : String,
  version : String,
) -> (String, String?) {
  let old = pinned_version(mod, name)
  match old {
    None => (mod, None)
    Some(was) =>
      if was == version {
        (mod, None)
      } else {
        let head = "\"" + name + "@"
        let lines : Array[String] = []
        for line in @text.split_char(mod, '\n') {
          let at = @text.index_of_str(line, head)
          if at < 0 {
            lines.push(line)
            continue
          }
          let start = at + head.length()
          let rest = line[start:].to_owned()
          let close = @text.index_of_str(rest, "\"")
          if close > 0 {
            lines.push(
              line[0:start].to_owned() + version + rest[close:].to_owned(),
            )
          } else {
            lines.push(line)
          }
        }
        (@text.join_lines(lines), Some(name + " " + was + " → " + version))
      }
  }
}

///|
/// `mctl upgrade <version>`: every name in `modules` moved to `version`, plus one
/// line per name that changed. A name the file does not pin is left alone and
/// reported as skipped — pinning it would be a change the user did not ask for.
pub fn upgrade_pins(
  mod : String,
  modules : Array[String],
  version : String,
) -> (String, Array[String]) {
  let changes : Array[String] = []
  let mut text = mod
  for m in modules {
    match pin_module(text, m, version) {
      (next, Some(change)) => {
        text = next
        changes.push(change)
      }
      (_, None) =>
        if pinned_version(text, m) == None {
          changes.push(m + " is not pinned, left alone")
        }
    }
  }
  (text, changes)
}
