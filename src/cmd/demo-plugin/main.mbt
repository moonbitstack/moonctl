// Reads the `{Api, ApiFilePath, Style, Dir}` JSON mctl writes to stdin, and prints
// a {"files":[...]} reply on stdout: a Markdown route listing plus a route count.
// It exercises the whole plugin contract end to end using only mctl's own
// (de)serialisers — including the style, which names what the plugin writes.

///|
async fn main {
  try {
    let req = @moonctl.plugin_from_json(@stdio.stdin.read_all().json())
    let spec = req.api
    let mut md = "# " +
      spec.service +
      " routes (from " +
      req.api_file_path +
      ")\n\n"
    for r in spec.routes {
      md = md + "- " + r.verb + " " + r.path + " -> " + r.handler
      if r.summary != "" {
        md = md + "  (" + r.summary + ")"
      }
      md = md + "\n"
    }
    let files : Array[@moonctl.GenFile] = [
      { path: spec.service + "_routes.md", content: md, },
      {
        path: spec.service + "_count.txt",
        content: spec.routes.length().to_string() + "\n",
      },
    ]
    @stdio.stdout.write(@moonctl.gen_files_to_json(files).stringify())
  } catch {
    e => @stdio.stderr.write("demo-plugin: " + e.to_string())
  }
}
