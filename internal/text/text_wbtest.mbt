///|
test "to_pascal converts snake_case operation names" {
  assert_eq(to_pascal("get_user"), "GetUser")
  assert_eq(to_pascal("ping"), "Ping")
  assert_eq(to_pascal("create_user_account"), "CreateUserAccount")
}

///|
test "to_pascal: snake table name to struct name" {
  assert_eq(to_pascal("users"), "Users")
  assert_eq(to_pascal("blog_posts"), "BlogPosts")
  assert_eq(to_pascal("api_key"), "ApiKey")
}

///|
test "snake_case conversion" {
  assert_eq(to_snake("SayHello"), "say_hello")
  assert_eq(to_snake("SayHelloAgain"), "say_hello_again")
  assert_eq(to_snake("HTTPServer"), "http_server")
  assert_eq(to_snake("Greeter"), "greeter")
  assert_eq(to_snake("already_snake"), "already_snake")
  assert_eq(to_snake("userID"), "user_id")
}
