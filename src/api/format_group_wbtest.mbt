///|
test "a type group indents its members one level like a nested block" {
  let messy =
    #|type (
    #|LoginReq {
    #|Username string `json:"username"`
    #|}
    #|Profile {
    #|Id int64 `json:"id"`
    #|}
    #|)
  inspect(
    format(messy),
    content=(
      #|type (
      #|  LoginReq {
      #|    Username string `json:"username"`
      #|  }
      #|  Profile {
      #|    Id int64 `json:"id"`
      #|  }
      #|)
      #|
    ),
  )
}

///|
test "a path parameter keeps its colon tight" {
  let messy =
    #|service user {
    #|get /profile/:id  (Profile)
    #|get /orders/:order/items/:item (Line)
    #|}
  // `: id` in the source would be a route that matches nothing, so the formatter
  // closes the gap rather than keep it
  inspect(
    format(messy),
    content=(
      #|service user {
      #|  get /profile/:id (Profile)
      #|  get /orders/:order/items/:item (Line)
      #|}
      #|
    ),
  )
}

///|
test "a group setting still gets its space after the colon" {
  let messy =
    #|@server(group:user, prefix:/api/v1)
    #|service user {
    #|get /ping
    #|}
  let once = format(messy)
  assert_eq(once.contains("@server (group: user, prefix: /api/v1)"), true)
}

///|
test "a type group with comments formats the same way twice" {
  let src =
    #|// the shapes this service trades in
    #|type (
    #|// who is asking
    #|LoginReq {
    #|Name string `json:"name"`
    #|}
    #|)
  let once = format(src)
  inspect(
    once,
    content=(
      #|// the shapes this service trades in
      #|type (
      #|  // who is asking
      #|  LoginReq {
      #|    Name string `json:"name"`
      #|  }
      #|)
      #|
    ),
  )
  inspect(format(once), content=once)
}
