///|
/// The plugin protocol round-trip (goctl's `api plugin`). mctl writes goctl's
/// request — `{Api, ApiFilePath, Style, Dir}` — to the plugin's stdin
/// (`plugin_request`); the plugin reads it back (`plugin_from_json`, or
/// `spec_from_json` when it wants nothing but the spec), emits the files it wants
/// written, and serialises them (`gen_files_to_json`); mctl reads that reply
/// (`parse_gen_files`) and writes the files to disk. Every stage here uses mctl's
/// own (de)serialisers, so the whole symmetric contract runs in one process — the
/// same one `cmd/demo-plugin` speaks over real pipes.
///
///     moon run src/examples/08-plugin
#coverage.skip
fn run_plugin(request : String) -> String raise {
  let req = @moonctl.plugin_from_json(@json.parse(request))
  let spec = req.api
  let mut md = "# " + spec.service + " routes (style " + req.style + ")\n\n"
  for r in spec.routes {
    md = md + "- " + r.verb + " " + r.path + " -> " + r.handler + "\n"
  }
  let files : Array[@moonctl.GenFile] = [
    { path: spec.service + "_routes.md", content: md, },
    {
      path: spec.service + "_count.txt",
      content: spec.routes.length().to_string() + "\n",
    },
  ]
  @moonctl.gen_files_to_json(files).stringify(indent=2)
}

///|
#coverage.skip
fn main raise {
  let source =
    #|service greet {
    #|  get  /ping       ping        "health check"
    #|  post /users      create_user "create a user"
    #|}
  let spec = @moonctl.parse(source)
  let request = @moonctl.plugin_request(
    spec,
    api_file_path="greet.api",
    style="go_zero",
    dir="out",
  )
  println("==== plugin_request(spec) -> plugin stdin ====\n")
  println(request)

  // The spec alone cannot tell a plugin where to write or how to spell what it
  // writes, so goctl's request carries the file, the style and the directory too.
  let req = @moonctl.plugin_from_json(@json.parse(request))
  println(
    "\nApiFilePath=\{req.api_file_path}  Style=\{req.style}  Dir=\{req.dir}",
  )
  try {
    let reply = run_plugin(request)
    println("\n==== plugin stdout: gen_files_to_json(files) ====\n")
    println(reply)
    println("\n==== parse_gen_files(reply) -> files mctl writes ====\n")
    for f in @moonctl.parse_gen_files(@json.parse(reply)) {
      println("---- " + f.path + " ----")
      println(f.content)
    }
  } catch {
    _ => println("plugin round-trip failed")
  }
}
