// The command table. `mctl help` prints it, `mctl completion` completes from it and
// the README lists it, so there is one description of every command and no second
// place for one to fall out of date.

///|
/// One command: what it is called, the line that shows how to call it, and one
/// sentence saying what it does.
pub(all) struct Command {
  name : String
  usage : String
  summary : String
}

///|
/// Every command mctl accepts, in the order `help` prints them: the generators, the
/// scaffolds, the spec tools, then the housekeeping.
pub fn commands() -> Array[Command] {
  [
    {
      name: "gen",
      usage: "mctl gen <api|rpc|model|crud|doc|gql|agent> <file>",
      summary: "generate a project tree, models or a document from a spec",
    },
    {
      name: "api",
      usage: "mctl api <format|validate|doc|ts|dart|kt|java> <file.api>",
      summary: "work on a .api spec itself: format it, check it, document it, or generate a client",
    },
    {
      name: "model",
      usage: "mctl model <new|datasource|mysql|pg|mongo|cache> …",
      summary: "read a schema — DDL, a live database, a spec — and write moonorm models",
    },
    {
      name: "gateway",
      usage: "mctl gateway <file.proto>",
      summary: "scaffold an HTTP gateway that fronts a moonrpc service",
    },
    {
      name: "migrate",
      usage: "mctl migrate <file.api>",
      summary: "write the SQL migrations a spec's models imply",
    },
    {
      name: "quickstart",
      usage: "mctl quickstart <name>",
      summary: "scaffold, generate and build a service in one step",
    },
    {
      name: "template",
      usage: "mctl template <list|show|init> [name]",
      summary: "list the bundled template library, or write one into a directory",
    },
    {
      name: "upgrade",
      usage: "mctl upgrade [version]",
      summary: "move the moonbitstack pins in moon.mod to a release",
    },
    {
      name: "config",
      usage: "mctl config <list|get|set|path|migrate> [key] [value]",
      summary: "read and write the mctl configuration file",
    },
    {
      name: "completion",
      usage: "mctl completion <bash|zsh|fish|powershell>",
      summary: "print a shell completion script for mctl",
    },
    {
      name: "bug",
      usage: "mctl bug [title]",
      summary: "print a bug report pre-filled with the environment",
    },
    {
      name: "env",
      usage: "mctl env",
      summary: "show the configuration mctl would use and where it came from",
    },
    {
      name: "docker",
      usage: "mctl docker <name>",
      summary: "write a Dockerfile and .dockerignore for a service",
    },
    {
      name: "kube",
      usage: "mctl kube <name>",
      summary: "write deployment and service manifests for a service",
    },
    {
      name: "plugin",
      usage: "mctl plugin <exe> <file.api>",
      summary: "run an external plugin over a spec, reading and writing JSON",
    },
    { name: "help", usage: "mctl help", summary: "print this message", },
  ]
}

///|
/// The words a shell should complete at the first position.
pub fn command_names() -> Array[String] {
  let out : Array[String] = []
  for c in commands() {
    out.push(c.name)
  }
  out
}

///|
/// The second word of a command that takes a sub-command, for a completion script
/// that completes two levels deep.
pub fn subcommands(name : String) -> Array[String] {
  match name {
    "gen" => ["api", "rpc", "model", "crud", "doc", "gql", "agent"]
    "api" => ["format", "validate", "doc", "ts", "dart", "kt", "java", "new"]
    "model" => ["new", "datasource", "mysql", "pg", "mongo", "cache"]
    "rpc" => ["new"]
    "gql" => ["new"]
    "mcp" => ["new"]
    "template" => ["list", "show", "init"]
    "config" => ["list", "get", "set", "path", "migrate"]
    "completion" => ["bash", "zsh", "fish", "powershell"]
    _ => []
  }
}

///|
/// The `mctl help` page: what mctl is, then one line per command, then the flags
/// every generator shares.
pub fn usage_text(version : String) -> String {
  let out : Array[String] = []
  out.push(
    "mctl " +
    version +
    " — a spec-driven generator for MoonBit services (← goctl)",
  )
  out.push("")
  out.push("usage:")
  let width = 34
  for c in commands() {
    out.push("  " + pad(c.usage, width) + c.summary)
  }
  out.push("")
  out.push("flags:")
  out.push(
    "  " +
    pad("--home <path>", width) +
    "use this template home instead of the bundled library",
  )
  out.push(
    "  " +
    pad("--remote <url>", width) +
    "read the template library from this git remote",
  )
  out.push(
    "  " +
    pad("--branch <name>", width) +
    "the branch of --remote to read (default: main)",
  )
  out.push(
    "  " +
    pad("--style <template>", width) +
    "how generated names are spelled: gozero (default), goZero, go_zero, …",
  )
  out.push(
    "  " +
    pad("--dir <path>", width) +
    "write the tree under <path> instead of here",
  )
  out.push(
    "  " +
    pad("--flat", width) +
    "write one <file>.mbt instead of a project tree",
  )
  out.push(
    "  " +
    pad("--write", width) +
    "rewrite the input file in place (api format)",
  )
  out.push("")
  out.push("`generate` is a synonym for `gen`, and `proto` for `rpc`.")
  out.push(
    "A .api spec may `import` others; they are read relative to the file that imports them.",
  )
  @text.join_lines(out)
}

///|
/// `s` padded with spaces to `n`, or returned as it is when it is longer.
fn pad(s : String, n : Int32) -> String {
  if s.length() >= n {
    return s + " "
  }
  let mut out = s
  while out.length() < n {
    out = out + " "
  }
  out
}

///|
/// A shell completion script for `shell`, or "" for a shell mctl has none for.
/// Completion is generated from `commands` and `subcommands`, so a new command is
/// completable the moment it is in the table.
pub fn completion(shell : String) -> String {
  let names = command_names().join(" ")
  let out : Array[String] = []
  match shell.to_lower() {
    "bash" => {
      out.push("# mctl bash completion — eval \"$(mctl completion bash)\"")
      out.push("_mctl() {")
      out.push("  local cur prev")
      out.push("  cur=\"${COMP_WORDS[COMP_CWORD]}\"")
      out.push("  prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
      out.push("  if [ \"$COMP_CWORD\" -eq 1 ]; then")
      out.push("    COMPREPLY=( $(compgen -W \"" + names + "\" -- \"$cur\") )")
      out.push("    return 0")
      out.push("  fi")
      out.push("  case \"$prev\" in")
      for c in commands() {
        let subs = subcommands(c.name)
        if subs.length() > 0 {
          out.push(
            "    " +
            c.name +
            ") COMPREPLY=( $(compgen -W \"" +
            subs.join(" ") +
            "\" -- \"$cur\") ); return 0 ;;",
          )
        }
      }
      out.push(
        "    completion) COMPREPLY=( $(compgen -W \"bash zsh fish powershell\" -- \"$cur\") ); return 0 ;;",
      )
      out.push("  esac")
      out.push("  COMPREPLY=( $(compgen -f -- \"$cur\") )")
      out.push("}")
      out.push("complete -F _mctl mctl")
    }
    "zsh" => {
      out.push("# mctl zsh completion — eval \"$(mctl completion zsh)\"")
      out.push("_mctl() {")
      out.push("  local -a cmds")
      out.push("  cmds=(" + names + ")")
      out.push("  if (( CURRENT == 2 )); then")
      out.push("    compadd -a cmds")
      out.push("    return")
      out.push("  fi")
      out.push("  case $words[2] in")
      for c in commands() {
        let subs = subcommands(c.name)
        if subs.length() > 0 {
          out.push("    " + c.name + ") compadd " + subs.join(" ") + " ;;")
        }
      }
      out.push("    *) _files ;;")
      out.push("  esac")
      out.push("}")
      out.push("compdef _mctl mctl")
    }
    "fish" => {
      out.push("# mctl fish completion — mctl completion fish | source")
      for c in commands() {
        out.push(
          "complete -c mctl -n \"__fish_use_subcommand\" -a \"" +
          c.name +
          "\" -d \"" +
          c.summary +
          "\"",
        )
      }
      for c in commands() {
        let subs = subcommands(c.name)
        for s in subs {
          out.push(
            "complete -c mctl -n \"__fish_seen_subcommand_from " +
            c.name +
            "\" -a \"" +
            s +
            "\"",
          )
        }
      }
    }
    "powershell" | "pwsh" => {
      out.push(
        "# mctl PowerShell completion — mctl completion powershell | Invoke-Expression",
      )
      out.push(
        "Register-ArgumentCompleter -Native -CommandName mctl -ScriptBlock {",
      )
      out.push("    param($wordToComplete, $commandAst, $cursorPosition)")
      out.push("    $commands = @('" + command_names().join("','") + "')")
      out.push(
        "    $commands | Where-Object { $_ -like \"$wordToComplete*\" } |",
      )
      out.push("        ForEach-Object {")
      out.push(
        "            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)",
      )
      out.push("        }")
      out.push("}")
    }
    _ => ()
  }
  @text.join_lines(out)
}
