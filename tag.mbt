// Struct tags. A `.api` field says where its value comes from and what it has to
// look like in the back-tick tag goctl borrowed from Go: `json:"name"` reads it out
// of the request body, `form:"page"` off the query string, `path:"id"` out of a URL
// segment, `header:"X-Trace"` off a request header, and the options after the wire
// name — `optional`, `default=`, `options=`, `range=` — constrain it. The parser
// keeps the tag verbatim on `Field.tag`; everything that reads one is here.

///|
/// Where a field's value is bound from (← goctl's struct tags): the request body
/// (`json:`, and an untagged field), the query string (`form:`), a URL segment
/// (`path:`), or a request header (`header:`).
pub(all) enum Bind {
  Body
  Query
  Path
  Header
} derive(Eq)

///|
pub extend Bind with Eq::{equal, not_equal}

///|
/// A `range=` constraint, e.g. `range=[1:120]` or `range=(0:]`. Each bound is
/// written as the spec wrote it and is empty when that end is open; `lo_inc` /
/// `hi_inc` say whether the bracket was inclusive (`[` `]`) or exclusive (`(` `)`).
pub(all) struct Range {
  lo : String
  hi : String
  lo_inc : Bool
  hi_inc : Bool
} derive(Eq)

///|
pub extend Range with Eq::{equal, not_equal}

///|
/// The binding key a tag carries and the body of its `"…"`, e.g. `path:"region"` →
/// `(Path, "region")`. When a tag names several the leftmost wins, and a field with
/// no binding tag reads out of the body.
fn tag_bind(tag : String) -> (Bind, String) {
  let mut at = -1
  let mut kind = Body
  let mut body = ""
  for
    probe in [
      ("json:\"", Body),
      ("form:\"", Query),
      ("path:\"", Path),
      ("header:\"", Header),
    ] {
    let found = index_of_str(tag, probe.0)
    if found < 0 || (at >= 0 && found >= at) {
      continue
    }
    let start = found + probe.0.length()
    let end = index_of(tag, '"', start)
    if end < 0 {
      continue
    }
    at = found
    kind = probe.1
    body = tag[start:end].to_owned()
  }
  (kind, body)
}

///|
/// A field's tag read apart: where it binds from, the wire name it binds under, and
/// the options that follow that name.
fn tag_read(f : Field) -> (Bind, String, Array[String]) {
  let (kind, body) = tag_bind(f.tag)
  let pieces = split_char(body, ',')
  let name = trim(pieces[0])
  let opts : Array[String] = []
  for i = 1; i < pieces.length(); i = i + 1 {
    let o = trim(pieces[i])
    if o != "" {
      opts.push(o)
    }
  }
  (kind, if name == "" { f.name } else { name }, opts)
}

///|
/// The value of the `key=` option in `opts`, or `None` when it carries none.
fn opt_value(opts : Array[String], key : String) -> String? {
  let head = key + "="
  for o in opts {
    if starts_with(o, head) {
      return Some(o[head.length():].to_owned())
    }
  }
  None
}

///|
/// Where this field's value is bound from: `form:` off the query string, `path:`
/// out of a URL segment, `header:` off a request header, and everything else — an
/// untagged field included — out of the request body.
pub fn Field::bind(self : Field) -> Bind {
  tag_read(self).0
}

///|
/// The name this field is carried under on the wire: the one its binding tag gives
/// (`json:"user_name"` → `user_name`, `form:"page"` → `page`, `path:"region"` →
/// `region`), with the options after it stripped, falling back to the field's own
/// name when it carries no tag.
pub fn Field::json_name(self : Field) -> String {
  tag_read(self).1
}

///|
/// The MoonBit spelling of this field: `snake_case`, because a MoonBit struct field
/// has to start lower-case — `UserName` is not one. Every generator that emits
/// MoonBit names the field with this, so the struct, the row decoder and the column
/// projection all agree; `json_name` is the wire side of the same field.
pub fn Field::mbt_name(self : Field) -> String {
  to_snake(self.name)
}

///|
/// Whether the tag marked this field `optional` (or Go's `omitempty`): it may be
/// absent, which is what keeps it out of a schema's `required` list.
pub fn Field::optional(self : Field) -> Bool {
  for o in tag_read(self).2 {
    if o == "optional" || o == "omitempty" {
      return true
    }
  }
  false
}

///|
/// The `default=` this field's tag declared, written the way the spec wrote it, or
/// `None` when it declared none.
pub fn Field::default_(self : Field) -> String? {
  opt_value(tag_read(self).2, "default")
}

///|
/// The values an `options=a|b|c` tag allows this field to take, empty when the tag
/// declared no such list.
pub fn Field::options(self : Field) -> Array[String] {
  let out : Array[String] = []
  match opt_value(tag_read(self).2, "options") {
    Some(v) =>
      for one in split_char(v, '|') {
        let t = trim(one)
        if t != "" {
          out.push(t)
        }
      }
    None => ()
  }
  out
}

///|
/// The `range=[lo:hi]` bounds this field's tag declared, or `None` when it declared
/// none. Either bound may be empty, which leaves that end open.
pub fn Field::range(self : Field) -> Range? {
  let raw = match opt_value(tag_read(self).2, "range") {
    Some(v) => trim(v)
    None => return None
  }
  let n = raw.length()
  if n < 3 {
    return None
  }
  let lo_inc = raw[0] == '['
  let hi_inc = raw[n - 1] == ']'
  if (lo_inc || raw[0] == '(') == false ||
    (hi_inc || raw[n - 1] == ')') == false {
    return None
  }
  let colon = index_of(raw, ':', 1)
  if colon < 0 {
    return None
  }
  Some({
    lo: trim(raw[1:colon].to_owned()),
    hi: trim(raw[colon + 1:n - 1].to_owned()),
    lo_inc,
    hi_inc,
  })
}
