///|
/// Whole-project scaffolds (goctl's `api new` / `rpc new` / `docker` / `kube`).
/// Each returns an `Array[GenFile] { path, content }` — a nested project tree the
/// `mctl` binary writes to disk. `scaffold_api`/`rpc`/`model` seed their source
/// through the same built-in generators the `gen` commands use, so a fresh tree
/// compiles out of the box; `scaffold_docker`/`kube` emit the deployment artefacts
/// (both take a `port?`, and `kube` a `replicas?`).
///
///     moon run src/examples/07-scaffold
#coverage.skip
fn dump(label : String, files : Array[@moonctl.GenFile]) -> Unit {
  println("==== \{label} -> \{files.length()} files ====")
  for f in files {
    println("---- \{f.path} (\{f.content.length()} bytes) ----")
    println(f.content)
  }
  println("")
}

///|
#coverage.skip
fn main {
  dump("scaffold_api(\"blog\")", @moonctl.scaffold_api("blog"))
  dump("scaffold_rpc(\"echo\")", @moonctl.scaffold_rpc("echo"))
  dump("scaffold_model(\"account\")", @moonctl.scaffold_model("account"))
  dump(
    "scaffold_docker(\"greet\", port=23333)",
    @moonctl.scaffold_docker("greet", port=23333),
  )
  dump(
    "scaffold_kube(\"greet\", replicas=233)",
    @moonctl.scaffold_kube("greet", replicas=233),
  )
}
