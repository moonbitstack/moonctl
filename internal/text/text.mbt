///|
pub fn is_ws(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
pub fn trim(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && is_ws(s[a]) {
    a = a + 1
  }
  while b > a && is_ws(s[b - 1]) {
    b = b - 1
  }
  s[a:b].to_owned()
}

///|
pub fn starts_with(s : String, prefix : String) -> Bool {
  let pn = prefix.length()
  if s.length() < pn {
    return false
  }
  for i = 0; i < pn; i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
pub fn index_of_str(hay : String, needle : String) -> Int32 {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
pub fn quote(s : String) -> String {
  "\"" + s + "\""
}

///|
pub fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Split `s` on `ch` (no quote handling; for `.a.b` field chains and `$var`
/// names).
pub fn split_char(s : String, ch : UInt16) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || s[i] == ch {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  out
}

///|
pub fn ends_with(s : String, suf : String) -> Bool {
  let sn = s.length()
  let fn_ = suf.length()
  if sn < fn_ {
    return false
  }
  for i = 0; i < fn_; i = i + 1 {
    if s[sn - fn_ + i] != suf[i] {
      return false
    }
  }
  true
}

///|
/// Split a URL path on `/`, dropping empty segments (so `/users/:id` → `["users",
/// ":id"]`).
pub fn path_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let n = path.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || path[i] == '/' {
      if i > start {
        out.push(path[start:i].to_owned())
      }
      start = i + 1
    }
  }
  out
}

///|
/// Join lines with `\n` (no trailing newline) — the codegen counterpart of
/// `commas` for multi-line blocks.
pub fn join_lines(parts : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + "\n"
    }
    out = out + parts[i]
  }
  out
}

///|
/// Uppercase a leading ASCII letter (MoonBit `String` has no `to_upper`, and only
/// the first letter of each `snake` word needs it for `PascalCase`).
pub fn upper_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let c = s[0].to_int()
  if c >= 0x61 && c <= 0x7A {
    match (c - 0x20).to_char() {
      Some(ch) => ch.to_string() + s[1:].to_owned()
      None => s
    }
  } else {
    s
  }
}

///|
/// Turn a `snake_case` table name into the `PascalCase` struct name its model maps
/// to (`blog_posts` → `BlogPosts`). Underscores split words; other characters carry
/// through.
pub fn to_pascal(s : String) -> String {
  let mut out = ""
  let mut word = ""
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == '_' {
      out = out + upper_first(word)
      word = ""
    } else {
      word = word + s[i:i + 1].to_owned()
    }
  }
  out + upper_first(word)
}

///|
/// Convert an identifier to `snake_case` (← protobuf's PascalCase RPC/service
/// names, which must become MoonBit value names). An uppercase letter starts a
/// new word when it follows a lowercase letter or digit, or when it is followed
/// by a lowercase letter (so `HTTPServer` → `http_server`, `SayHello` →
/// `say_hello`). Existing underscores are preserved and the result is lowercased.
pub fn to_snake(s : String) -> String {
  let n = s.length()
  let mut r = ""
  for i = 0; i < n; i = i + 1 {
    let c = s[i].to_int()
    let is_upper = c >= 0x41 && c <= 0x5A
    if is_upper && i > 0 {
      let prev = s[i - 1].to_int()
      let prev_lower_or_digit = (prev >= 0x61 && prev <= 0x7A) ||
        (prev >= 0x30 && prev <= 0x39)
      let next_lower = i + 1 < n &&
        ({
          let nx = s[i + 1].to_int()
          nx >= 0x61 && nx <= 0x7A
        })
      if prev_lower_or_digit || next_lower {
        r = r + "_"
      }
    }
    r = r + s[i:i + 1].to_owned()
  }
  r.to_lower()
}
