///|
/// How `moon.mod` writes an import of `dep` at its pin.
fn pinned(dep : String) -> String {
  "\"" + dep + "@" + pins.get(dep).unwrap() + "\""
}

///|
fn contains(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
/// Every path of `tree`, newline-joined.
fn paths(tree : Array[TreeFile]) -> String {
  let mut out = ""
  for f in tree {
    out = if out == "" { f.path } else { out + "\n" + f.path }
  }
  out
}
