// goctl's `--style` is a naming template, not a fixed set of cases. The template is
// `<before>GO<through>ZERO<after>`: the casing of the `GO` marker sets the first
// word's case, the casing of `ZERO` sets every later word's, and `<through>` is what
// goes between them. So `gozero` names `welcometogozero`, `goZero` names
// `welcomeToGoZero`, `go_zero` names `welcome_to_go_zero`, and `Go#zero` names
// `Welcome#to#go#zero`. Everything moonctl invents a name for — the files of a
// generated tree and the handler/logic/middleware entry points inside them — is
// spelled through one of these.

///|
/// A `--style` template that is not `<before>GO<through>ZERO<after>`: either a
/// marker is missing (`go`, `zero`), they are the wrong way round, or one is cased
/// neither `go`/`GO`/`Go` nor `zero`/`ZERO`/`Zero` (`gOZero`, `goZEro`).
pub suberror StyleError {
  BadStyle(String)
}

///|
impl Show for StyleError with fn output(self, logger) {
  match self {
    BadStyle(s) =>
      logger.write_string(
        "style \"" + s + "\" is not <before>GO<through>ZERO<after>",
      )
  }
}

///|
/// The case a marker asks its words to be spelled in.
enum Case {
  Lower
  Upper
  Title
}

///|
/// Uppercase every ASCII letter (`String` has no `to_upper`).
fn upper_all(s : String) -> String {
  let mut out = ""
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c >= 0x61 && c <= 0x7A {
      out = out +
        (match (c - 0x20).to_char() {
          Some(ch) => ch.to_string()
          None => s[i:i + 1].to_owned()
        })
    } else {
      out = out + s[i:i + 1].to_owned()
    }
  }
  out
}

///|
/// Whether `c` is an ASCII capital — the letter that starts a new word.
fn is_cap(c : UInt16) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
/// The words of `name`: `_` separates them, and a capital starts a new one, so
/// `welcome_to_go_zero` and `WelcomeToGoZero` both split into four.
fn words(name : String) -> Array[String] {
  let out : Array[String] = []
  let mut w = ""
  for i = 0; i < name.length(); i = i + 1 {
    let c = name[i]
    if c == '_' {
      if w != "" {
        out.push(w)
        w = ""
      }
    } else if is_cap(c) && w != "" {
      out.push(w)
      w = name[i:i + 1].to_owned()
    } else {
      w = w + name[i:i + 1].to_owned()
    }
  }
  if w != "" {
    out.push(w)
  }
  out
}

///|
/// The case a marker is written in, or `None` when it is written in none of them.
fn case_of(marker : String) -> Case? {
  let lower = marker.to_lower()
  if marker == lower {
    Some(Lower)
  } else if marker == upper_all(lower) {
    Some(Upper)
  } else if marker == @text.upper_first(lower) {
    Some(Title)
  } else {
    None
  }
}

///|
fn cased(w : String, c : Case) -> String {
  match c {
    Lower => w.to_lower()
    Upper => upper_all(w)
    Title => @text.upper_first(w.to_lower())
  }
}

///|
/// A `--style` naming template (← goctl's `--style`), ready to spell names with.
/// Build one with `Style::parse`, apply it with `Style::format`.
pub struct Style {
  before : String
  through : String
  after : String
  head : Case
  tail : Case
}

///|
/// goctl's default style, `gozero`: every word lower-cased and run together.
pub fn Style::gozero() -> Style {
  { before: "", through: "", after: "", head: Lower, tail: Lower, }
}

///|
/// Read a `--style` template. It must contain `GO` and then `ZERO` — in any case,
/// with anything before, between and after them:
///
/// ```
/// Style::parse("gozero").format("welcome_to_go_zero")  // welcometogozero
/// Style::parse("goZero").format("welcome_to_go_zero")  // welcomeToGoZero
/// Style::parse("go_zero").format("welcome_to_go_zero") // welcome_to_go_zero
/// Style::parse("Go#zero").format("welcome_to_go_zero") // Welcome#to#go#zero
/// ```
///
/// The `GO` marker's own casing (`go`, `GO` or `Go`) says how the first word is
/// spelled, `ZERO`'s says how every later word is, and what stands between the two
/// markers is what stands between the words. A template missing a marker (`go`,
/// `zero`), holding them in the wrong order, or casing one of them any other way
/// (`gOZero`, `goZEro`) raises `StyleError`.
pub fn Style::parse(s : String) -> Style raise StyleError {
  let up = upper_all(s)
  let go = @text.index_of_str(up, "GO")
  let zero = @text.index_of_str(up, "ZERO")
  if go < 0 || zero < go + 2 {
    raise BadStyle(s)
  }
  let head = match case_of(s[go:go + 2].to_owned()) {
    Some(c) => c
    None => raise BadStyle(s)
  }
  let tail = match case_of(s[zero:zero + 4].to_owned()) {
    Some(c) => c
    None => raise BadStyle(s)
  }
  {
    before: s[0:go].to_owned(),
    through: s[go + 2:zero].to_owned(),
    after: s[zero + 4:].to_owned(),
    head,
    tail,
  }
}

///|
/// Spell `name` in this style. `name` is split into words on `_` and before each
/// capital, the first word takes the `GO` marker's case and the rest take `ZERO`'s,
/// and they are joined with whatever stood between the markers.
pub fn Style::format(self : Style, name : String) -> String {
  let ws = words(name)
  let mut out = ""
  for i = 0; i < ws.length(); i = i + 1 {
    if i > 0 {
      out = out + self.through
    }
    out = out + cased(ws[i], if i == 0 { self.head } else { self.tail })
  }
  self.before + out + self.after
}
