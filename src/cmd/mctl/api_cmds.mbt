// `mctl api …` — the sub-commands that work on a `.api` spec rather than turning it
// into a project: `format`, `validate`, `doc`, and the four clients. All of them
// read the spec (following its imports), so a spec that composes other specs
// formats, validates and generates as one file.

///|
/// `mctl api format <file>` — write the canonical spelling of the spec to stdout,
/// or over the file itself with `--write`. A spec that will not parse is reported
/// with the line that broke it, and the file is left alone.
async fn api_format(input : String, write : Bool) -> Unit {
  try {
    let source = @fs.read_file(input).text()
    let text = @moonctl.format(source)
    if write {
      @fs.write_file(input, text, create_mode=CreateOrTruncate)
      println("mctl: formatted " + input)
    } else {
      println(text)
    }
  } catch {
    e => println("mctl: cannot format " + input + ": " + e.to_string())
  }
}

///|
/// `mctl api validate <file>` — every finding, in spec order, then a count. A spec
/// with no finding prints one line saying so, which is what a script checks.
async fn api_validate(input : String) -> Unit {
  try {
    let files = read_files(input)
    let source = match files.get(input) {
      Some(s) => s
      None => ""
    }
    let found = @moonctl.validate_files(source, files, from=input)
    for d in found {
      println(d.to_string())
    }
    let mut errors = 0
    for d in found {
      if d.severity == @moonctl.Severity::Error {
        errors = errors + 1
      }
    }
    if found.length() == 0 {
      println("mctl: " + input + " is valid")
    } else {
      println(
        "mctl: " +
        input +
        ": " +
        errors.to_string() +
        " error(s), " +
        (found.length() - errors).to_string() +
        " warning(s)",
      )
    }
  } catch {
    e => println("mctl: cannot validate " + input + ": " + e.to_string())
  }
}

///|
/// `mctl api doc <file>` — the Markdown reference of the spec, written beside it as
/// `<stem>_api.md`.
async fn api_doc(input : String) -> Unit {
  try {
    let spec = read_spec(input)
    let out = replace_ext(input, ".api", "_api.md")
    @fs.write_file(
      out,
      @moonctl.generate_markdown(spec),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: cannot document " + input + ": " + e.to_string())
  }
}

///|
/// The directory `input` sits in, with its trailing separator, or "" when it sits in
/// the current one.
fn dir_of(input : String) -> String {
  let mut last = -1
  for i = 0; i < input.length(); i = i + 1 {
    let c = input[i]
    if c == '/' || c == '\\' {
      last = i
    }
  }
  if last < 0 {
    ""
  } else {
    input[0:last + 1].to_owned()
  }
}

///|
/// `mctl api ts|dart|kt|java <file>` — the typed client of one language, written
/// beside the spec: `<stem>_client.<ext>`, and `GreetClient.java` for Java, which
/// requires the file to be named after its public class.
async fn api_client(input : String, lang : @moonctl.Lang) -> Unit {
  try {
    let spec = read_spec(input)
    let out = dir_of(input) + @moonctl.client_file_name(lang, spec.service)
    @fs.write_file(
      out,
      @moonctl.generate_client(spec, lang),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + out + " (" + lang.label() + ") from " + input)
  } catch {
    e =>
      println(
        "mctl: cannot generate a " +
        lang.label() +
        " client from " +
        input +
        ": " +
        e.to_string(),
      )
  }
}
