///|
/// The spec the client tests generate from: a body, a path segment, a query
/// parameter, a header, an optional field, a list, a nested type and a route with no
/// types at all, which between them cover every branch of the four emitters.
const SAMPLE : String =
  #|@server(group: user, prefix: /api/v1)
  #|service greet {
  #|    @doc "create a user"
  #|    @handler createUser
  #|    post /users (CreateReq) returns (User)
  #|
  #|    @handler getUser
  #|    get /users/:id (GetReq) returns (User)
  #|
  #|    @handler ping
  #|    get /ping
  #|}
  #|
  #|type GetReq {
  #|    id: int64 `path:"id"`
  #|    verbose: bool `form:"verbose,optional"`
  #|}
  #|
  #|type CreateReq {
  #|    name: string `json:"name"`
  #|    tags: []string `json:"tags"`
  #|    owner: User `json:"owner"`
  #|    note: string? `json:"note"`
  #|    client: string `header:"X-Client-Id"`
  #|}
  #|
  #|type User {
  #|    id: int64 `json:"id"`
  #|    name: string `json:"name"`
  #|    nickname: string `json:"nickname,optional"`
  #|}

///|
/// Whether `hay` contains `needle` — the assertion a generated file is checked with,
/// since what matters about a client is that the lines that carry a route are there.
fn has(hay : String, needle : String) -> Bool {
  @text.index_of_str(hay, needle) >= 0
}

///|
/// The sample spec, parsed.
fn sample() -> @api.Spec raise {
  @api.parse(SAMPLE)
}

///|
test "a client file is named after its service" {
  assert_eq(client_file_name(TypeScript, "greet"), "greet_client.ts")
  assert_eq(client_file_name(Dart, "greet"), "greet_client.dart")
  assert_eq(client_file_name(Kotlin, "greet"), "greet_client.kt")
  // javac requires a public class to live in a file of its own name
  assert_eq(client_file_name(Java, "greet"), "GreetClient.java")
  assert_eq(client_file_name(TypeScript, ""), "api_client.ts")
}

///|
test "the language records its extension and its name" {
  assert_eq(TypeScript.ext(), "ts")
  assert_eq(Kotlin.label(), "Kotlin")
  assert_eq(Java.ext(), "java")
}

///|
test "typescript: an interface per type and a fetch per route" {
  let ts = generate_client(sample(), TypeScript)
  assert_eq(has(ts, "export interface User {"), true)
  // a field the tag marks optional is optional in the interface and nullable in it
  assert_eq(has(ts, "  nickname?: string | null;"), true)
  // `int64` is a `number` here: TypeScript has one numeric type
  assert_eq(has(ts, "  id: number;"), true)
  // a body route takes the request type as its one parameter and returns the response
  assert_eq(
    has(
      ts, "async createUser(body: CreateReq, xClientId: string): Promise<User> {",
    ),
    true,
  )
  // the path segment is escaped, not pasted
  assert_eq(
    has(
      ts,
      "const path = `/api/v1/users/" +
      interp_open() +
      "encodeURIComponent(String(id))}`;",
    ),
    true,
  )
  // `form:` is a query parameter, and an optional one is only sent when set
  assert_eq(has(ts, "if (verbose !== undefined && verbose !== null) {"), true)
  assert_eq(
    has(ts, "query.push(\"verbose=\" + encodeURIComponent(String(verbose)));"),
    true,
  )
  // `header:` is a header, under the wire name the tag gave
  assert_eq(has(ts, "headers[\"X-Client-Id\"] = String(xClientId);"), true)
  // a nested type is encoded through its own function, with its wire names
  assert_eq(has(ts, "out[\"owner\"] = userToJson(value.owner);"), true)
  // a route with no response returns void and still reports a failed status
  assert_eq(has(ts, "async ping(): Promise<void> {"), true)
  assert_eq(has(ts, "throw new ApiError(res.status, text);"), true)
}

///|
test "dart: a class per type, fromJson and toJson, a Send port" {
  let dart = generate_client(sample(), Dart)
  assert_eq(has(dart, "import 'dart:convert';"), true)
  assert_eq(has(dart, "class User {"), true)
  assert_eq(
    has(dart, "  factory User.fromJson(Map<String, dynamic> j) {"),
    true,
  )
  assert_eq(has(dart, "  Map<String, dynamic> toJson() {"), true)
  assert_eq(has(dart, "    return User("), true)
  // a body is positional, everything else is a named parameter
  assert_eq(
    has(
      dart, "Future<User> createUser(CreateReq body, {required String xClientId}) async {",
    ),
    true,
  )
  assert_eq(
    has(dart, "Future<User> getUser({required int id, bool? verbose}) async {"),
    true,
  )
  assert_eq(
    has(
      dart,
      "final path = '/api/v1/users/" +
      interp_open() +
      "Uri.encodeComponent(id.toString())}';",
    ),
    true,
  )
  assert_eq(has(dart, "throw ApiException(res.status, res.body);"), true)
}

///|
test "kotlin: a data class with fromWire, two ports, default arguments" {
  let kt = generate_client(sample(), Kotlin)
  assert_eq(has(kt, "data class User("), true)
  assert_eq(has(kt, "fun fromWire(m: Map<String, Any?>): User = User("), true)
  assert_eq(has(kt, "fun interface Transport {"), true)
  assert_eq(has(kt, "interface Codec {"), true)
  // an optional parameter is a defaulted one, so a caller writes only what it has
  assert_eq(
    has(kt, "fun getUser(id: Long, verbose: Boolean? = null): User {"),
    true,
  )
  assert_eq(has(kt, "val path = \"/api/v1/users/\" + enc(id)"), true)
  assert_eq(
    has(kt, "token?.let { headers[\"authorization\"] = \"Bearer \" + it }"),
    true,
  )
}

///|
test "java: one public class, nested models, an overload for optional parameters" {
  let java = generate_client(sample(), Java)
  assert_eq(has(java, "public final class GreetClient {"), true)
  assert_eq(has(java, "    public static final class User {"), true)
  assert_eq(
    has(java, "        public static User fromWire(Map<String, Object> m) {"),
    true,
  )
  assert_eq(has(java, "        public Long id;"), true)
  assert_eq(
    has(java, "    public User getUser(long id, Boolean verbose) {"),
    true,
  )
  // Java has no default arguments, so the shorter call is a real method
  assert_eq(has(java, "    public User getUser(long id) {"), true)
  assert_eq(has(java, "        return getUser(id, null);"), true)
  assert_eq(has(java, "throw new ApiException(res.status, res.body);"), true)
}

///|
test "a spec with no service name still generates a client" {
  let source =
    #|service greet {
    #|    @handler ping
    #|    get /ping
    #|}
  let spec = @api.parse(source)
  assert_eq(has(generate_client(spec, TypeScript), "class GreetClient {"), true)
  assert_eq(
    has(generate_client(spec, TypeScript), "async ping(): Promise<void> {"),
    true,
  )
}
