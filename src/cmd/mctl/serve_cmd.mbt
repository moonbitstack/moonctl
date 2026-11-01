// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How long a stopped server has to finish what it is doing before it is killed, in milliseconds.
let stop_timeout : Int32 = 5000

///|
/// Build `pkg`, the compiler's output going where the user can read it, and say where the
/// executable is. `None` is a build that failed.
async fn build_server(pkg : String) -> String? {
  let (code, output) = @process.collect_stdout("moon", [
    "run", pkg, "--target", "native", "--build-only",
  ])
  guard code == 0 else {
    println(output.text())
    return None
  }
  @cli.built_binary(output.text().trim().to_owned())
}

///|
/// Every watched source under `dirs`, with when it last changed. A deletion changes the map as
/// surely as a save does.
async fn source_times(dirs : Array[String]) -> Map[String, (Int64, Int32)] {
  let times : Map[String, (Int64, Int32)] = Map([])
  for root in dirs {
    @fs.walk(
      root,
      (dir, names) => {
        for name in names {
          if @cli.is_watched(name) {
            let path = "\{dir}/\{name}"
            times[path] = @fs.mtime(path) catch { _ => (0L, 0) }
          }
        }
      },
      exclude=@cli.is_skipped,
      allow_failure=true,
    )
  }
  times
}

///|
/// Wait until something under `dirs` differs from `before`.
async fn sources_change(
  dirs : Array[String],
  before : Map[String, (Int64, Int32)],
  delay : Int32,
) -> Unit {
  for ;; {
    @async.sleep(delay)
    if source_times(dirs) != before {
      return
    }
  }
}

///|
/// Run the server once, with the exit code it leaves.
async fn run_server(path : String, args : Array[String]) -> Int32 {
  @process.run(
    path,
    args,
    cancel_handler=@process.graceful_cancel(timeout=stop_timeout),
  )
}

///|
/// `mctl serve`: build a package and run it, and with `--reload` build and run it again whenever a
/// source changes (← `uvicorn --reload`). The running server stops before the build, since Windows
/// will not overwrite a running executable; a build that fails leaves nothing running until the
/// next save fixes it. Stopping `mctl` stops the server.
async fn cmd_serve(argv : Array[String]) -> Unit {
  let plan = @cli.parse_serve(argv[:]) catch {
    e => {
      println("mctl: \{e}")
      return
    }
  }
  if !plan.reload {
    guard build_server(plan.pkg) is Some(path) else {
      println("mctl: the build failed")
      return
    }
    run_server(path, plan.args) |> ignore
    return
  }
  for ;; {
    let before = source_times(plan.dirs)
    let built = build_server(plan.pkg)
    @async.with_task_group(group => {
      let server = match built {
        Some(path) =>
          Some(
            group.spawn(allow_failure=true, () => {
              run_server(path, plan.args) |> ignore
            }),
          )
        None => {
          println("mctl: the build failed, waiting for a change")
          None
        }
      }
      sources_change(plan.dirs, before, plan.delay)
      if server is Some(task) {
        task.cancel()
      }
    })
    println("mctl: sources changed, rebuilding")
  }
}
