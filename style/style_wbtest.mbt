///|
/// `name` spelled in `style`, or the complaint the template raised.
fn styled(style : String, name : String) -> String {
  Style::parse(style).format(name) catch {
    e => Show::to_string(e)
  }
}

///|
test "each documented style spells the sample its own way" {
  let sample = "welcome_to_go_zero"
  inspect(styled("gozero", sample), content="welcometogozero")
  inspect(styled("goZero", sample), content="welcomeToGoZero")
  inspect(styled("go_zero", sample), content="welcome_to_go_zero")
  inspect(styled("Go#zero", sample), content="Welcome#to#go#zero")
}

///|
test "the sample splits the same however it is already spelled" {
  inspect(styled("go_zero", "WelcomeToGoZero"), content="welcome_to_go_zero")
  inspect(styled("goZero", "welcometogozero"), content="welcometogozero")
  inspect(styled("GO_ZERO", "welcome_to_go_zero"), content="WELCOME_TO_GO_ZERO")
}

///|
test "a template without both markers, or with one miscased, is refused" {
  let sample = "welcome_to_go_zero"
  inspect(
    styled("go", sample),
    content="style \"go\" is not <before>GO<through>ZERO<after>",
  )
  inspect(
    styled("zero", sample),
    content="style \"zero\" is not <before>GO<through>ZERO<after>",
  )
  inspect(
    styled("zerogo", sample),
    content="style \"zerogo\" is not <before>GO<through>ZERO<after>",
  )
  inspect(
    styled("gOZero", sample),
    content="style \"gOZero\" is not <before>GO<through>ZERO<after>",
  )
  inspect(
    styled("goZEro", sample),
    content="style \"goZEro\" is not <before>GO<through>ZERO<after>",
  )
}

///|
test "before and after the markers carry through" {
  inspect(
    styled("api-goZero.mbt", "ping_handler"),
    content="api-pingHandler.mbt",
  )
}

///|
test "the default style is gozero" {
  inspect(Style::gozero().format("ping_handler"), content="pinghandler")
}
