// A template library read from disk (`--home`) or from a git checkout (`--remote`).
//
// The bundled library is code: the scaffolds in `scaffold/` write their files
// directly. A template library is the other half of goctl's model — a directory of
// files with `{{.Field}}` holes, rendered against the parsed spec — so a team can
// keep its own service layout without forking mctl. Both the file's path and its
// text are rendered: `{{.service}}.mbt` names the entry point after the service.

///|
/// One file of a template directory: where it sits relative to the directory's root,
/// and what is in it. Both are templates over the spec.
pub(all) struct TemplateFile {
  path : String
  text : String
}

///|
/// Render `t`'s path and text over `spec`, returning the file to write. A path is
/// rendered like any other template, so `{{.service}}/moon.mod` becomes
/// `greet/moon.mod`.
pub fn render_template_file(
  spec : @api.Spec,
  t : TemplateFile,
) -> (String, String) raise @template.Refused {
  (render_path(spec, t.path), generate_with(spec, t.text))
}

///|
/// A file path rendered through the same engine as the contents, so a library has
/// one syntax to learn. A path with no `{{` in it is returned untouched.
fn render_path(
  spec : @api.Spec,
  path : String,
) -> String raise @template.Refused {
  if @text.index_of_str(path, "{{") < 0 {
    return path
  }
  generate_with(spec, path)
}

///|
/// Render every file of a template directory. The result is in the order the caller
/// listed them, so a file that has to exist first (a `moon.mod`) can be put first.
pub fn render_template_dir(
  spec : @api.Spec,
  files : Array[TemplateFile],
) -> Array[(String, String)] raise @template.Refused {
  let out : Array[(String, String)] = []
  for f in files {
    out.push(render_template_file(spec, f))
  }
  out
}
