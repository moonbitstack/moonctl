// `api format`: the canonical spelling of an `.api` spec (← goctl's `api format`).
//
// The formatter works on lines, not on the parse tree: a spec's comments, its
// group annotations and the exact text of its struct tags are the author's, and a
// round trip through `Spec` would drop every one of them. What it does normalise is
// the layout — one leading pair of spaces per nesting level, single spaces between
// words, `key: value` in a group, one blank line between blocks, one newline at the
// end — which is what makes `format` idempotent and what makes a diff between two
// runs empty.

///|
/// Two spaces per nesting level — the indent a formatted spec uses.
fn indent(depth : Int32) -> String {
  let mut out = ""
  let mut i = 0
  while i < depth {
    out = out + "  "
    i = i + 1
  }
  out
}

///|
/// `line` with its trailing whitespace cut and every leading tab read as two
/// spaces, so a spec indented in an editor that inserts tabs still formats to the
/// same text as one indented with spaces. Tabs *inside* a line are left alone: a
/// struct tag or a quoted summary may legitimately carry one.
fn normalize_leading_ws(line : String) -> String {
  let n = line.length()
  let mut end = n
  while end > 0 {
    let c = line[end - 1]
    if @text.is_ws(c) {
      end = end - 1
    } else {
      break
    }
  }
  let mut start = 0
  let mut out = ""
  while start < end && (line[start] == ' ' || line[start] == '\t') {
    if line[start] == '\t' {
      out = out + "  "
    } else {
      out = out + " "
    }
    start = start + 1
  }
  out + line[start:end].to_owned()
}

///|
/// Split a line into its code and its `//` comment (comment included as written,
/// empty when there is none). A `//` inside a quoted summary or a back-tick tag is
/// part of the code, not the start of a comment.
fn split_comment(line : String) -> (String, String) {
  let n = line.length()
  let mut in_str = false
  let mut in_tag = false
  for i = 0; i < n; i = i + 1 {
    let c = line[i]
    if c == '"' && in_tag == false {
      in_str = in_str == false
    } else if c == '`' && in_str == false {
      in_tag = in_tag == false
    } else if c == '/' &&
      in_str == false &&
      in_tag == false &&
      i + 1 < n &&
      line[i + 1] == '/' {
      return (line[0:i].to_owned(), line[i:].to_owned())
    }
  }
  (line, "")
}

///|
/// Collapse every run of whitespace outside a quoted string and a back-tick tag
/// into one space, and put that space where the language wants it: after a comma
/// and after a colon, never before one, never inside `()`, and always before `{`.
fn collapse(code : String) -> String {
  let n = code.length()
  let mut out = ""
  let mut i = 0
  let mut in_str = false
  let mut in_tag = false
  let mut pending = false
  let mut force = false
  let mut path_param = false
  while i < n {
    let c = code[i]
    if in_str == false && in_tag == false && @text.is_ws(c) {
      pending = true
      i = i + 1
      continue
    }
    if in_str == false && in_tag == false {
      let last = last_char(out)
      let want = (pending || force) &&
        (path_param == false || is_word_char(c) == false) &&
        out.length() > 0 &&
        last != '(' &&
        last != ' ' &&
        c != ')' &&
        c != ',' &&
        c != ':' &&
        c != '}'
      if want {
        out = out + " "
      }
      if c == '{' && last_char(out) != ' ' && last_char(out) != '{' {
        out = out + " "
      }
    }
    let before = last_char(out)
    out = out + code[i:i + 1].to_owned()
    if in_str == false && in_tag == false {
      // `key:value` in a group wants the space; `:id` in a path does not. A
      // colon right after a slash names a path parameter, and a space there
      // would turn `/profile/:id` into a route that matches nothing.
      if c == ':' {
        if before == '/' {
          path_param = true
        } else {
          force = true
        }
      } else {
        force = false
        if path_param && is_word_char(c) == false {
          path_param = false
        }
      }
      // a comma is followed by one space, the way a group lists its settings
      if c == ',' {
        pending = true
      }
    }
    if c != ',' {
      pending = false
    }
    if c == '"' && in_tag == false {
      in_str = in_str == false
    } else if c == '`' && in_str == false {
      in_tag = in_tag == false
    }
    i = i + 1
  }
  out
}

///|
/// `key:value` with the one space the language asks for; used inside a group.
fn normalize_pair(piece : String) -> String {
  let t = @text.trim(piece)
  let colon = index_of(t, ':', 0)
  if colon <= 0 {
    return t
  }
  let key = @text.trim(t[0:colon].to_owned())
  let value = @text.trim(t[colon + 1:].to_owned())
  if value == "" {
    key + ":"
  } else {
    key + ": " + value
  }
}

///|
/// Rebuild a `@server( … )` line as `@server(key: value, key: value)`, splitting on
/// the commas outside a quoted value. A line that does not close its parenthesis on
/// the same line keeps the open paren bare, so a multi-line group indents cleanly.
fn normalize_server(t : String) -> String {
  let open = index_of(t, '(', 0)
  if open < 0 {
    return t
  }
  let close = index_of(t, ')', open + 1)
  if close < 0 {
    return "@server ("
  }
  let body = @text.trim(t[open + 1:close].to_owned())
  let pieces : Array[String] = []
  if body != "" {
    for piece in split_commas(body) {
      let p = normalize_pair(piece)
      if p != "" {
        pieces.push(p)
      }
    }
  }
  "@server (" + join_with(pieces, ", ") + ")" + t[close + 1:].to_owned()
}

///|
/// `parts` joined with `sep`.
fn join_with(parts : Array[String], sep : String) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + sep
    }
    out = out + parts[i]
  }
  out
}

///|
/// The canonical spelling of one line of a spec: whitespace collapsed, `@server`
/// rebuilt, and the author's comment re-attached after the code.
fn normalize_line(line : String) -> String {
  let (code, comment) = split_comment(line)
  let mut body = collapse(@text.trim(code))
  if @text.starts_with(body, "@server") {
    body = normalize_server(body)
  }
  if comment == "" {
    body
  } else if body == "" {
    @text.trim(comment)
  } else {
    body + " " + @text.trim(comment)
  }
}

///|
/// The last character of `s`, or `' '` when it has none.
fn last_char(s : String) -> UInt16 {
  if s.length() == 0 {
    ' '
  } else {
    s[s.length() - 1]
  }
}

///|
/// Whether `c` may appear in a name — the letters, digits and underscore a path
/// parameter is spelled with.
fn is_word_char(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Format an `.api` source. Nesting is read off braces and off the two blocks that
/// open with a parenthesis — a multi-line `@server (` and a `type (` group; blank
/// lines collapse to one; the result ends in exactly one newline. Comments and
/// struct tags survive verbatim, and the function is idempotent: formatting an
/// already formatted spec returns it unchanged.
pub fn format(source : String) -> String {
  let out : Array[String] = []
  let mut depth = 0
  let mut blank = false
  let mut in_server = false
  let mut in_type = false
  for raw in lines(source) {
    let line = normalize_leading_ws(raw)
    let text = normalize_line(line)
    if text == "" {
      if out.length() > 0 {
        blank = true
      }
      continue
    }
    if blank && out.length() > 0 {
      out.push("")
      blank = false
    }
    let closes = @text.starts_with(text, "}") ||
      (in_server && text == ")") ||
      (in_type && text == ")")
    let d = if closes && depth > 0 { depth - 1 } else { depth }
    out.push(indent(d) + text)
    if closes {
      if depth > 0 {
        depth = depth - 1
      }
      if in_server && text == ")" {
        in_server = false
      }
      if in_type && text == ")" {
        in_type = false
      }
    }
    if last_char(text) == '{' {
      depth = depth + 1
    } else if text == "@server (" {
      in_server = true
      depth = depth + 1
    } else if text == "type (" {
      in_type = true
      depth = depth + 1
    }
  }
  let mut result = ""
  for i = 0; i < out.length(); i = i + 1 {
    if i > 0 {
      result = result + "\n"
    }
    result = result + out[i]
  }
  result + "\n"
}
