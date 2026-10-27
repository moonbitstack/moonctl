///|
/// The words and flags `argv` splits into, written as `words | style dir flat`.
fn split_note(argv : Array[String]) -> String {
  let (words, opts) = split_flags(argv)
  let mut ws = ""
  for w in words {
    ws = if ws == "" { w } else { ws + " " + w }
  }
  ws + " | " + opts.style + " " + opts.dir + " " + opts.flat.to_string()
}

///|
test "a flag is read in both spellings, and only a flag is taken for one" {
  inspect(
    split_note(["gen", "api", "greet.api"]),
    content="gen api greet.api | gozero  false",
  )
  inspect(
    split_note(["gen", "api", "greet.api", "--style", "go_zero", "--dir", "out"]),
    content="gen api greet.api | go_zero out false",
  )
  inspect(
    split_note([
      "gen", "api", "greet.api", "--style=goZero", "--dir=out", "--flat",
    ]),
    content="gen api greet.api | goZero out true",
  )
  // a flag with nothing after it is a word, not a flag that ate the next command
  inspect(
    split_note(["gen", "api", "x.api", "--style"]),
    content="gen api x.api --style | gozero  false",
  )
}

///|
/// Whether `hay` carries `needle`.
fn has(hay : String, needle : String) -> Bool {
  let hn = hay.length()
  let nn = needle.length()
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  nn == 0
}

///|
test "a plugin run hands over the program, its argv and goctl's four keys" {
  let spec = @moonctl.parse("service greet {\n  @handler ping\n  get /ping\n}")
  let (bin, argv, req) = plugin_call(
    "mctl-plugin --out docs",
    spec,
    "api/greet.api",
    { style: "go_zero", dir: "out", flat: false, },
  )
  // the invocation is split, so a plugin taking arguments is run with them
  assert_eq(bin, "mctl-plugin")
  assert_eq(argv, ["--out", "docs"])
  // and the request is goctl's envelope, not the bare spec
  assert_eq(has(req, "\"Api\": {"), true)
  assert_eq(has(req, "\"ApiFilePath\": \"api/greet.api\""), true)
  assert_eq(has(req, "\"Style\": \"go_zero\""), true)
  assert_eq(has(req, "\"Dir\": \"out\""), true)
}

///|
test "a known extension is replaced, an unknown one is kept" {
  inspect(replace_ext("greet.api", ".api", ".mbt"), content="greet.mbt")
  inspect(
    replace_ext("greet.proto", ".proto", "_grpc.mbt"),
    content="greet_grpc.mbt",
  )
  inspect(replace_ext("greet", ".api", "_model.mbt"), content="greet_model.mbt")
  inspect(
    replace_ext("api/greet.api", ".api", "_openapi.json"),
    content="api/greet_openapi.json",
  )
}
