///|
test "a rule that fits in a line is written on one, and one that does not is split" {
  // `moon fmt` keeps the two shapes apart at 80 columns; a generated `moon.mod`
  // has to be in the shape it would leave it in
  inspect(
    rule_line("orm", "moonx x"),
    content="rule(name: \"orm\", command: \"moonx x\")\n",
  )
  let long = rule_line(
    "orm", "moonx moonbitstack/moonorm/cmd/orm@0.11.7 -C \"$mod_dir\" \"$input\" -o \"$output\"",
  )
  assert_eq(long.contains("rule(\n  name: \"orm\",\n  command: "), true)
  assert_eq(long.contains(",\n)\n"), true)
}
