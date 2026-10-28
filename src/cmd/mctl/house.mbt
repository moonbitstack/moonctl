// The housekeeping commands: `help`, `completion`, `template`, `config`, `env`,
// `bug`, `upgrade`, `quickstart`, and the `model mysql|pg datasource` spellings.
//
// The logic — the command table, the completion scripts, the config file, the pin
// rewrite — lives in `moonbitstack/moonctl/cli` and is pure. What is here is the
// part that needs a machine: which file the config is in, which variables are set,
// what is on disk.

///|
/// The version this binary reports. `moon.mod` carries the same number; a release
/// bumps both, and `mctl upgrade` reads the one in `moon.mod`.
const MCTL_VERSION : String = "0.12.1"

///|
/// Where the configuration file is: `MOONCTL_CONFIG` when it is set, otherwise
/// `.mctl/config` under the user's home directory.
fn config_path() -> String {
  match @env.get_env_var("MOONCTL_CONFIG") {
    Some(p) => p
    None =>
      match @env.get_env_var("HOME") {
        Some(h) => h + "/.mctl/config"
        None =>
          match @env.get_env_var("USERPROFILE") {
            Some(h) => h + "/.mctl/config"
            None => ".mctl/config"
          }
      }
  }
}

///|
/// The configuration as it sits on disk, or the default one when there is no file.
async fn read_config() -> @moonctl.Config {
  let path = config_path()
  try {
    if @fs.exists(path) == false {
      return @moonctl.default_config()
    }
    @moonctl.parse_config(@fs.read_file(path).text())
  } catch {
    _ => @moonctl.default_config()
  }
}

///|
/// Write a configuration, creating `~/.mctl` when it is not there yet.
async fn write_config(c : @moonctl.Config) -> Unit {
  let path = config_path()
  let dir = dir_of(path)
  if dir != "" && @fs.exists(dir) == false {
    @fs.mkdir(dir)
  }
  @fs.write_file(path, @moonctl.config_text(c), create_mode=CreateOrTruncate)
}

///|
/// The rows `mctl env` and `mctl bug` report: what mctl resolved, in the order a
/// reader wants it.
fn env_rows(c : @moonctl.Config) -> Array[(String, String)] {
  let rows : Array[(String, String)] = []
  rows.push(("config", config_path()))
  rows.push(
    ("home", if c.home == "" { "(bundled template library)" } else { c.home }),
  )
  rows.push(("remote", c.remote))
  rows.push(("branch", c.branch))
  rows.push(("style", c.style))
  rows.push(
    (
      "templates",
      if c.templates.length() == 0 {
        "(none pinned)"
      } else {
        c.templates.join(", ")
      },
    ),
  )
  for key in ["MOONCTL_HOME", "MOONCTL_REMOTE", "MOONCTL_BRANCH"] {
    match @env.get_env_var(key) {
      Some(v) => rows.push((key, v))
      None => ()
    }
  }
  match @env.current_dir() {
    Some(d) => rows.push(("working dir", d))
    None => ()
  }
  rows
}

///|
/// `mctl env` — what mctl would use, and where each value came from.
async fn cmd_env() -> Unit {
  println(@moonctl.env_report(MCTL_VERSION, env_rows(read_config())))
}

///|
/// `mctl bug [title]` — a report with the environment already filled in.
async fn cmd_bug(title : String) -> Unit {
  println(@moonctl.bug_report(title, MCTL_VERSION, env_rows(read_config())))
}

///|
/// `mctl completion <shell>` — a completion script for that shell.
fn cmd_completion(shell : String) -> Unit {
  let script = @moonctl.completion(shell)
  if script == "" {
    println(
      "mctl: no completion for \"" +
      shell +
      "\"; try bash, zsh, fish or powershell",
    )
  } else {
    println(script)
  }
}

///|
/// `mctl template <list|show> [name]` — the bundled library.
fn cmd_template(args : Array[String]) -> Unit {
  let what = if args.length() > 0 { args[0] } else { "list" }
  match what {
    "list" =>
      for line in @text.split_char(@moonctl.template_table(), '\n') {
        println(line)
      }
    "show" =>
      if args.length() < 2 {
        println("mctl: template show <name>")
      } else {
        match @moonctl.find_template(args[1]) {
          Some(t) =>
            for line in @text.split_char(@moonctl.template_detail(t), '\n') {
              println(line)
            }
          None =>
            println(
              "mctl: no template \"" +
              args[1] +
              "\"; `mctl template list` shows them all",
            )
        }
      }
    _ => println("mctl: template <list|show> [name]")
  }
}

///|
/// `mctl config [list|get|set|path|migrate] [key] [value]` — the configuration file.
/// `set` creates the file when it is not there, and a key mctl does not know is
/// refused rather than written, so the file never collects typos.
async fn cmd_config(args : Array[String]) -> Unit {
  let what = if args.length() > 0 { args[0] } else { "list" }
  match what {
    "path" => println(config_path())
    "list" =>
      for line in @text.split_char(@moonctl.config_text(read_config()), '\n') {
        println(line)
      }
    "get" =>
      if args.length() < 2 {
        println(
          "mctl: config get <key>; keys: " + @moonctl.config_keys().join(", "),
        )
      } else {
        match @moonctl.config_get(read_config(), args[1]) {
          Some(v) => println(v)
          None =>
            println(
              "mctl: no key \"" +
              args[1] +
              "\"; keys: " +
              @moonctl.config_keys().join(", "),
            )
        }
      }
    "set" =>
      if args.length() < 3 {
        println("mctl: config set <key> <value>")
      } else {
        let key = args[1]
        if @moonctl.config_keys().contains(key) == false {
          println(
            "mctl: no key \"" +
            key +
            "\"; keys: " +
            @moonctl.config_keys().join(", "),
          )
        } else {
          try {
            write_config(@moonctl.config_set(read_config(), key, args[2]))
            println("mctl: " + key + " = " + args[2] + " in " + config_path())
          } catch {
            e =>
              println(
                "mctl: cannot write " + config_path() + ": " + e.to_string(),
              )
          }
        }
      }
    "migrate" =>
      try {
        let path = config_path()
        let text = if @fs.exists(path) {
          @fs.read_file(path).text()
        } else {
          ""
        }
        let (next, changes) = @moonctl.migrate_config(text)
        write_config(@moonctl.parse_config(next))
        if changes.length() == 0 {
          println("mctl: " + path + " is already current")
        } else {
          for c in changes {
            println("mctl: " + c)
          }
          println("mctl: wrote " + path)
        }
      } catch {
        e => println("mctl: cannot migrate the config: " + e.to_string())
      }
    _ => println("mctl: config <list|get|set|path|migrate> [key] [value]")
  }
}

///|
/// `mctl upgrade <version>` — move every moonbitstack pin in `moon.mod` to
/// `version`, reporting each one. Nothing else in the file is touched.
async fn cmd_upgrade(version : String) -> Unit {
  let path = "moon.mod"
  try {
    let mod = @fs.read_file(path).text()
    let names : Array[String] = []
    for p in @moonctl.mod_pins(mod) {
      if @text.starts_with(p.0, "moonbitstack/") {
        names.push(p.0)
      }
    }
    if names.length() == 0 {
      println("mctl: " + path + " pins no moonbitstack module")
      return
    }
    let (next, changes) = @moonctl.upgrade_pins(mod, names, version)
    @fs.write_file(path, next, create_mode=CreateOrTruncate)
    for c in changes {
      println("mctl: " + c)
    }
    println("mctl: wrote " + path)
  } catch {
    e => println("mctl: cannot upgrade " + path + ": " + e.to_string())
  }
}

///|
/// `mctl quickstart <name>` — a project you can `moon check`, in one command: the
/// api scaffold, then what to run next.
async fn cmd_quickstart(name : String) -> Unit {
  write_scaffold("api project " + name, @moonctl.scaffold_api(name))
  println("")
  println("mctl: next:")
  println("  cd " + name)
  println("  mctl api validate api/" + name + ".api")
  println("  mctl api ts api/" + name + ".api")
  println("  moon check --target all")
}

///|
/// `mctl migrate <file.api>` — the SQL a spec's types imply, written beside the spec
/// as `<service>_migrate.sql`.
async fn cmd_migrate(input : String) -> Unit {
  try {
    let spec = read_spec(input)
    let out = dir_of(input) + @moonctl.migrate_file_name(spec.service)
    @fs.write_file(
      out,
      @moonctl.generate_migrations(spec),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: cannot migrate " + input + ": " + e.to_string())
  }
}

///|
/// `mctl model mysql|pg datasource <dsn>` — the same reflection `model datasource`
/// runs, written under a name that says which engine it read. The DSN decides how
/// to connect; the prefix only decides what the file is called, so an engine the
/// DSN names differently is still written where a reader looks for it.
async fn gen_datasource_for(kind : String, dsn : String) -> Unit {
  gen_datasource(dsn, kind + "_model.mbt")
}
