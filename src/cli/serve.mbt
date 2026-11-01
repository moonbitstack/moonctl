// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// `mctl serve`, the half of uvicorn's `--reload` a compiled language needs a tool for: a server
// cannot re-import its modules, so something outside it has to rebuild and restart it. Reading the
// command line and telling what changed are here, without touching the disk; the binary owns the
// processes.

///|
/// How long to wait between looks at the sources, in milliseconds (← uvicorn's `--reload-delay`,
/// 0.25 seconds).
pub let reload_delay : Int32 = 250

///|
/// Which directories are watched when none are named (← uvicorn's `--reload-dir`, the current
/// directory).
pub let reload_dirs : Array[String] = ["."]

///|
/// What `mctl serve` was asked to do: the package to build and run, whether to rebuild it on change,
/// where and how often to look, and the arguments that go to the server.
pub(all) struct Serve {
  pkg : String
  reload : Bool
  dirs : Array[String]
  delay : Int32
  args : Array[String]
}

///|
/// Read `mctl serve [package] [--reload] [--reload-dir dir]... [--reload-delay seconds] [-- args]`.
/// Everything after `--` is the server's own.
pub fn parse_serve(argv : ArrayView[String]) -> Serve raise {
  let mut pkg : String? = None
  let mut reload = false
  let dirs : Array[String] = []
  let mut delay = reload_delay
  let args : Array[String] = []
  let mut i = 0
  let value = (flag : String) => {
    guard i + 1 < argv.length() else { fail("\{flag} needs a value") }
    i = i + 1
    argv[i]
  }
  while i < argv.length() {
    match argv[i] {
      "--" => {
        args.push_iter(argv[i + 1:].iter())
        break
      }
      "--reload" => reload = true
      "--reload-dir" => dirs.push(value("--reload-dir"))
      "--reload-delay" => {
        let seconds = value("--reload-delay")
        let parsed = @json.parse(seconds) catch {
          _ => fail("--reload-delay takes seconds, not \{seconds}")
        }
        guard parsed is Number(n, ..) && n > 0.0 else {
          fail("--reload-delay takes seconds, not \{seconds}")
        }
        delay = (n * 1000.0).to_int()
      }
      flag if flag.has_prefix("--") => fail("mctl serve: unknown flag \{flag}")
      name => {
        guard pkg is None else { fail("mctl serve: one package, not two") }
        pkg = Some(name)
      }
    }
    i = i + 1
  }
  {
    pkg: pkg.unwrap_or("."),
    reload,
    dirs: if dirs.length() == 0 {
      reload_dirs
    } else {
      dirs
    },
    delay,
    args,
  }
}

///|
/// Whether a save to this file calls for a rebuild: MoonBit source, or the manifests that say how
/// it is built.
pub fn is_watched(name : String) -> Bool {
  name.has_suffix(".mbt") ||
  name.has_suffix(".mbti") ||
  name == "moon.pkg" ||
  name == "moon.mod"
}

///|
/// Whether a directory is left out of the walk: what the build itself writes, and anything hidden.
pub fn is_skipped(dir : String) -> Bool {
  let parts = dir.split("/").collect()
  let base = parts[parts.length() - 1].to_owned()
  base == "_build" ||
  base == "target" ||
  (base.has_prefix(".") && base != "." && base != "..")
}

///|
/// The executable a `moon run --build-only` built, from what it prints.
pub fn built_binary(output : String) -> String? {
  let json = @json.parse(output) catch { _ => return None }
  guard json is Object(fields) else { return None }
  guard fields.get("artifacts_path") is Some(Array(paths)) else { return None }
  match paths {
    [String(path), ..] => Some(path)
    _ => None
  }
}
