// `mctl config` — the settings mctl reads before it starts: where the template
// library lives (`home`, `remote`, `branch`), how generated names are spelled
// (`style`), and which templates a bare `gen` picks (`template`).
//
// The file is `key = value` per line, `#` starts a comment. That is deliberately
// dull: it diffs cleanly, a human can edit it without a schema, and a v1 file —
// uppercase environment-style keys — is migrated by `migrate_config`, which reports
// every key it changed.

///|
/// One configuration: the fields mctl understands. `version` is the file format,
/// not the mctl version, and it goes up when `migrate_config` learns a new shape.
pub(all) struct Config {
  version : Int32
  home : String
  remote : String
  branch : String
  style : String
  templates : Array[String]
}

///|
/// The file mctl writes when there is none yet: the bundled library, the default
/// branch, the `gozero` spelling.
pub fn default_config() -> Config {
  {
    version: 2,
    home: "",
    remote: "https://github.com/moonbitstack/templates",
    branch: "main",
    style: "gozero",
    templates: [],
  }
}

///|
/// `line` split at its first `=`, both halves trimmed, or `None` when it has no `=`
/// or opens with `#`.
fn config_pair(line : String) -> (String, String)? {
  let s = @text.trim(line)
  if s == "" || s[0] == '#' {
    return None
  }
  let eq = @text.index_of_str(s, "=")
  if eq <= 0 {
    return None
  }
  Some((@text.trim(s[0:eq].to_owned()), @text.trim(s[eq + 1:].to_owned())))
}

///|
/// Read a configuration. A key mctl does not know is kept out of the result rather
/// than refused, so a file written by a newer mctl still loads. An empty or
/// unreadable-text file is the default configuration.
pub fn parse_config(text : String) -> Config {
  let mut c = default_config()
  for line in @text.split_char(text, '\n') {
    match config_pair(line) {
      None => ()
      Some(kv) => {
        let key = kv.0.to_lower()
        let value = kv.1
        match key {
          "version" =>
            match parse_int(value) {
              Some(v) =>
                c = {
                  version: v,
                  home: c.home,
                  remote: c.remote,
                  branch: c.branch,
                  style: c.style,
                  templates: c.templates,
                }
              None => ()
            }
          "home" | "moontcl_home" | "moonctl_home" =>
            c = {
              version: c.version,
              home: value,
              remote: c.remote,
              branch: c.branch,
              style: c.style,
              templates: c.templates,
            }
          "remote" | "moonctl_remote" =>
            c = {
              version: c.version,
              home: c.home,
              remote: value,
              branch: c.branch,
              style: c.style,
              templates: c.templates,
            }
          "branch" | "moonctl_branch" =>
            c = {
              version: c.version,
              home: c.home,
              remote: c.remote,
              branch: value,
              style: c.style,
              templates: c.templates,
            }
          "style" | "moonctl_style" =>
            c = {
              version: c.version,
              home: c.home,
              remote: c.remote,
              branch: c.branch,
              style: value,
              templates: c.templates,
            }
          "template" | "moonctl_template" =>
            if value != "" && c.templates.contains(value) == false {
              c = {
                version: c.version,
                home: c.home,
                remote: c.remote,
                branch: c.branch,
                style: c.style,
                templates: c.templates + [value],
              }
            }
          _ => ()
        }
      }
    }
  }
  c
}

///|
/// A decimal integer read out of `s`, or `None` when `s` is not one.
fn parse_int(s : String) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c - '0').to_int()
  }
  Some(n)
}

///|
/// The configuration as the file it is stored in, with a comment saying what the
/// file is for and where the keys come from.
pub fn config_text(c : Config) -> String {
  let out : Array[String] = []
  out.push(
    "# mctl configuration — written by `mctl config set`, safe to edit by hand.",
  )
  out.push(
    "# `home` is a template library on disk; `remote` and `branch` are read when",
  )
  out.push("# there is no `home`, or when --remote is passed.")
  out.push("")
  out.push("version = " + c.version.to_string())
  out.push("home = " + c.home)
  out.push("remote = " + c.remote)
  out.push("branch = " + c.branch)
  out.push("style = " + c.style)
  for t in c.templates {
    out.push("template = " + t)
  }
  @text.join_lines(out) + "\n"
}

///|
/// The value of one key, or `None` when mctl has no such key.
pub fn config_get(c : Config, key : String) -> String? {
  match key.to_lower() {
    "version" => Some(c.version.to_string())
    "home" => Some(c.home)
    "remote" => Some(c.remote)
    "branch" => Some(c.branch)
    "style" => Some(c.style)
    "template" => Some(c.templates.join(", "))
    _ => None
  }
}

///|
/// `c` with one key set. `template` appends — a config may name several — while a
/// scalar key replaces what was there. An unknown key is returned unchanged, so a
/// caller checks the key against `config_keys` first.
pub fn config_set(c : Config, key : String, value : String) -> Config {
  match key.to_lower() {
    "home" => { ..c, home: value, }
    "remote" => { ..c, remote: value, }
    "branch" => { ..c, branch: value, }
    "style" => { ..c, style: value, }
    "template" =>
      if c.templates.contains(value) {
        c
      } else {
        { ..c, templates: c.templates + [value], }
      }
    _ => c
  }
}

///|
/// The keys `config get` and `config set` accept.
pub fn config_keys() -> Array[String] {
  ["version", "home", "remote", "branch", "style", "template"]
}

///|
/// A v1 configuration — the uppercase, environment-style keys mctl read before it
/// had a file — rewritten as the current shape. Returns the new text and one line
/// per key that changed, so `mctl config migrate` can say what it did.
pub fn migrate_config(text : String) -> (String, Array[String]) {
  let changes : Array[String] = []
  let mut c = default_config()
  let mut seen_version = false
  for line in @text.split_char(text, '\n') {
    match config_pair(line) {
      None => ()
      Some(kv) => {
        let raw_key = kv.0
        let low = raw_key.to_lower()
        let value = kv.1
        let canonical = if low == "moontcl_home" ||
          low == "moonctl_home" ||
          low == "goctl_home" {
          "home"
        } else if low == "moonctl_remote" || low == "goctl_remote" {
          "remote"
        } else if low == "moonctl_branch" {
          "branch"
        } else if low == "moonctl_style" {
          "style"
        } else if low == "moonctl_template" || low == "goctl_template" {
          "template"
        } else {
          low
        }
        if canonical == "version" {
          seen_version = true
        }
        if canonical != raw_key && config_keys().contains(canonical) {
          changes.push("\"" + raw_key + "\" → \"" + canonical + "\"")
        }
        let before = config_get(c, canonical)
        c = config_set(c, canonical, value)
        if canonical == "version" {
          match parse_int(value) {
            Some(1) => c = { ..c, version: 2, }
            _ => ()
          }
        }
        if canonical == "template" {
          let after = config_get(c, canonical)
          if before != after {
            changes.push("kept template \"" + value + "\"")
          }
        }
      }
    }
  }
  if seen_version == false {
    changes.push("added \"version = 2\"")
  }
  (config_text(c), changes)
}
