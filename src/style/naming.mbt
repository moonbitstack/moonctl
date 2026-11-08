// What a spec's own names become in SQL. `--style` names what mctl invents — the
// files of a tree and the functions inside them — and deliberately leaves the
// names the spec chose alone, because a MoonBit type has to keep its capital. A
// table and a column are neither: they are names the schema implies, and a team
// whose tables are `Users` and whose columns are `createdAt` should say so once, in
// the spec, rather than rename them in every generated file.
//
// The spec says it in its `info` block, next to the title and the version:
//
//   info (
//     tableNaming:  "plural_snake"
//     columnNaming: "camel"
//   )

///|
/// The casing a generated name takes.
pub(all) enum Naming {
  /// `created_at`: every word lower-cased, joined by `_`.
  Snake
  /// `createdAt`: the first word lower-cased, the rest capitalized, run together.
  Camel
  /// `CreatedAt`: every word capitalized, run together.
  Pascal
  /// `created-at`: every word lower-cased, joined by `-`.
  Kebab
  /// `CREATED_AT`: every word upper-cased, joined by `_`.
  ScreamingSnake
}

///|
/// How a spec's own names are spelled in SQL: the table a `type` block becomes,
/// its columns, and whether a table is named for one row (`user`) or for the set
/// (`users`).
pub(all) struct NamingPolicy {
  table : Naming
  column : Naming
  plural : Bool
}

///|
/// The policy a spec that says nothing gets: lower snake for both, one row per
/// name — the spelling every SQL style guide starts from.
pub let default_naming : NamingPolicy = {
  table: Snake,
  column: Snake,
  plural: false,
}

///|
/// A `Naming` as its option spells it: `snake`, `camel`, `pascal`, `kebab` or
/// `screaming`. `plural_snake` is `snake` with plural tables, and `pluralSnake`
/// spells the same.
fn naming_of_option(text : String) -> (Naming, Bool)? {
  match @text.trim(text).to_lower() {
    "snake" => Some((Snake, false))
    "camel" => Some((Camel, false))
    "pascal" => Some((Pascal, false))
    "kebab" => Some((Kebab, false))
    "screaming" | "screaming_snake" | "screamingsnake" =>
      Some((ScreamingSnake, false))
    "plural_snake" | "pluralsnake" | "plural" => Some((Snake, true))
    _ => None
  }
}

///|
/// The policy a spec's `info` block asks for, or `None` when it asks for none —
/// which leaves each generator spelling names the way it always has. A value that
/// is not a casing is left at the default and named by `naming_problems`, which
/// `validate` reports, so generation never guesses a spelling the spec did not ask
/// for.
pub fn NamingPolicy::of_info(info : Array[(String, String)]) -> NamingPolicy? {
  let mut policy = default_naming
  let mut asked = false
  for kv in info {
    match @text.trim(kv.0).to_lower() {
      "tablenaming" | "table_naming" | "naming.table" =>
        match naming_of_option(kv.1) {
          Some((naming, plural)) => {
            policy = { ..policy, table: naming, }
            if plural {
              policy = { ..policy, plural: true, }
            }
            asked = true
          }
          None => ()
        }
      "columnnaming" | "column_naming" | "naming.column" =>
        match naming_of_option(kv.1) {
          Some((naming, _)) => {
            policy = { ..policy, column: naming, }
            asked = true
          }
          None => ()
        }
      "tableplural" | "table_plural" | "naming.plural" => {
        let value = @text.trim(kv.1).to_lower()
        if value == "true" || value == "false" {
          policy = { ..policy, plural: value == "true", }
          asked = true
        }
      }
      _ => ()
    }
  }
  if asked {
    Some(policy)
  } else {
    None
  }
}

///|
/// What the spec's `info` block says that `NamingPolicy` could not read, one line
/// per entry, for `validate` to report: a naming key with a value that is not a
/// casing, or with no value at all.
pub fn naming_problems(info : Array[(String, String)]) -> Array[String] {
  let out : Array[String] = []
  for kv in info {
    let key = @text.trim(kv.0).to_lower()
    let known = key == "tablenaming" ||
      key == "table_naming" ||
      key == "naming.table" ||
      key == "columnnaming" ||
      key == "column_naming" ||
      key == "naming.column" ||
      key == "tableplural" ||
      key == "table_plural" ||
      key == "naming.plural"
    if known == false {
      continue
    }
    if key == "tableplural" || key == "table_plural" || key == "naming.plural" {
      let value = @text.trim(kv.1).to_lower()
      if value != "true" && value != "false" {
        out.push("info " + kv.0 + ": want true or false, got \"" + kv.1 + "\"")
      }
    } else if naming_of_option(kv.1) is None {
      out.push(
        "info " +
        kv.0 +
        ": want snake, camel, pascal, kebab, screaming or plural_snake, got \"" +
        kv.1 +
        "\"",
      )
    }
  }
  out
}

///|
/// `name` in this casing.
pub fn Naming::spell(self : Naming, name : String) -> String {
  let ws = words(name)
  let parts : Array[String] = []
  for i = 0; i < ws.length(); i = i + 1 {
    let w = ws[i]
    parts.push(
      match self {
        Snake | Kebab => w.to_lower()
        ScreamingSnake => upper_all(w.to_lower())
        Camel =>
          if i == 0 {
            w.to_lower()
          } else {
            @text.upper_first(w.to_lower())
          }
        Pascal => @text.upper_first(w.to_lower())
      },
    )
  }
  let gap = match self {
    Kebab => "-"
    Camel | Pascal => ""
    _ => "_"
  }
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + gap
    }
    out = out + parts[i]
  }
  out
}

///|
/// `word` in the plural, by the two rules that cover most English nouns: `y` after
/// a consonant becomes `ies`, a sibilant takes `es`, and everything else takes `s`.
/// It is a rule, not a dictionary — a name it gets wrong is spelled by asking for
/// `snake` tables instead of `plural_snake`.
fn plural(word : String) -> String {
  let w = word.to_lower()
  let n = w.length()
  if n == 0 {
    return word
  }
  if n >= 2 && w[n - 1] == 'y' {
    let before = w[n - 2]
    let vowel = before == 'a' ||
      before == 'e' ||
      before == 'i' ||
      before == 'o' ||
      before == 'u'
    if vowel == false {
      return w[0:n - 1].to_owned() + "ies"
    }
  }
  if @text.ends_with(w, "s") ||
    @text.ends_with(w, "x") ||
    @text.ends_with(w, "z") ||
    @text.ends_with(w, "ch") ||
    @text.ends_with(w, "sh") {
    return w + "es"
  }
  w + "s"
}

///|
/// The table a `type` block called `name` becomes, under this policy.
pub fn NamingPolicy::table_name(self : NamingPolicy, name : String) -> String {
  if self.plural == false {
    return self.table.spell(name)
  }
  // The plural is the last word's: `BlogPost` is `blog_posts`, not `blogs_posts`.
  let ws = words(name)
  let out : Array[String] = []
  for i = 0; i < ws.length(); i = i + 1 {
    out.push(if i + 1 == ws.length() { plural(ws[i]) } else { ws[i] })
  }
  self.table.spell(out.join("_"))
}

///|
/// The column a field called `name` becomes, under this policy.
pub fn NamingPolicy::column_name(self : NamingPolicy, name : String) -> String {
  self.column.spell(name)
}
