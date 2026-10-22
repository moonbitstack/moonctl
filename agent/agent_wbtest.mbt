///|
test "generate_agent emits a Tool per route and assembles an AIAgent" {
  let src =
    #|service greet {
    #|  get  /ping        ping        "health check"
    #|  get  /users/:id   get_user
    #|  post /users       create_user "create a user"
    #|}
  let code = generate_agent(@api.parse(src))
  // one tool struct + impls per route
  assert_eq(code.contains("priv struct GetUserTool {}"), true)
  assert_eq(
    code.contains("impl @tools.Tool for GetUserTool with fn descriptor"),
    true,
  )
  assert_eq(code.contains("name: \"get_user\""), true)
  assert_eq(code.contains("description: \"get /users/:id\""), true)
  assert_eq(
    code.contains("impl @tools.Tool for CreateUserTool with fn execute_raw"),
    true,
  )
  // the assembly registers every tool and builds the agent
  assert_eq(code.contains("pub fn build_agent("), true)
  assert_eq(code.contains(".add(PingTool::{  })"), true)
  assert_eq(code.contains(".add(GetUserTool::{  })"), true)
  assert_eq(code.contains(".add(CreateUserTool::{  })"), true)
  assert_eq(
    code.contains("system_prompt=Some(\"You are the greet assistant.\")"),
    true,
  )
}
