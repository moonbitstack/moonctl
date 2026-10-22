///|
/// Look up a string-valued key in a JSON object, or `""` if absent / not a string.
fn jstr(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Look up an object-valued key, or an empty map if absent / not an object.
fn jobj(obj : Map[String, Json], key : String) -> Map[String, Json] {
  match obj.get(key) {
    Some(Object(m)) => m
    _ => Map([])
  }
}

///|
/// The content of the file at `path` among `files`, or `""` if none matches.
fn file_at(files : Array[@plugin.GenFile], path : String) -> String {
  for f in files {
    if f.path == path {
      return f.content
    }
  }
  ""
}

///|
/// One step down a document, by name or by index.
fn down(doc : Json, path : ArrayView[String]) -> Json? {
  let mut here = doc
  for step in path {
    here = match here {
      Object(members) =>
        match members.get(step) {
          Some(next) => next
          None => return None
        }
      Array(items) => {
        let mut index = 0
        for c in step {
          index = index * 10 + (c.to_int() - '0'.to_int())
        }
        if index < 0 || index >= items.length() {
          return None
        }
        items[index]
      }
      _ => return None
    }
  }
  Some(here)
}

///|
test "generated OpenAPI 3.1 parses and carries the expected paths" {
  let src =
    #|service greet {
    #|  get  /ping        ping        "health check"
    #|  get  /users/:id   get_user
    #|  get  /users       list_users
    #|  post /users       create_user "create a user"
    #|}
    #|
    #|type User {
    #|  id:   int64
    #|  name: string
    #|}
  let spec = @api.parse(src)
  let js = @doc.generate_doc(spec, version=OpenApi31, api_version="1.2.3")
  let parsed = @json.loads(js)
  let root = match parsed {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(root, "openapi"), "3.1.0")
  assert_eq(jstr(jobj(root, "info"), "title"), "greet")
  assert_eq(jstr(jobj(root, "info"), "version"), "1.2.3")
  let paths = jobj(root, "paths")
  // `:id` became `{id}`; each verb is present under its path
  assert_eq(paths.contains("/ping"), true)
  assert_eq(paths.contains("/users/{id}"), true)
  assert_eq(paths.contains("/users"), true)
  let users = jobj(paths, "/users")
  assert_eq(users.contains("get"), true)
  assert_eq(users.contains("post"), true)
  // operationId + summary carried through
  assert_eq(jstr(jobj(users, "post"), "operationId"), "create_user")
  assert_eq(jstr(jobj(users, "post"), "summary"), "create a user")
  // path parameter for /users/{id}
  let get_user = jobj(jobj(paths, "/users/{id}"), "get")
  let params = match get_user.get("parameters") {
    Some(Array(a)) => a
    _ => []
  }
  assert_eq(params.length(), 1)
  let p0 = match params[0] {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(p0, "name"), "id")
  assert_eq(jstr(p0, "in"), "path")
  // OpenAPI 3.x nests the param type under `schema`
  assert_eq(jstr(jobj(p0, "schema"), "type"), "string")
  // the `type` block became a component schema with typed properties
  let schemas = jobj(jobj(root, "components"), "schemas")
  assert_eq(schemas.contains("User"), true)
  let user = jobj(schemas, "User")
  assert_eq(jstr(user, "type"), "object")
  let props = jobj(user, "properties")
  assert_eq(jstr(jobj(props, "id"), "format"), "int64")
  assert_eq(jstr(jobj(props, "name"), "type"), "string")
}

///|
test "scaffold_api emits a compilable moonapi project tree" {
  let files = scaffold_api("greet")
  assert_eq(files.length(), 5)
  let m = file_at(files, "greet/moon.mod")
  assert_eq(contains(m, "name = \"greet\""), true)
  assert_eq(contains(m, pinned("moonbitstack/moonapi")), true)
  assert_eq(contains(m, pinned("moonbitstack/moonasgi")), true)
  let pkg = file_at(files, "greet/src/moon.pkg")
  assert_eq(
    pkg, "import {\n  \"moonbitstack/moonapi\",\n  \"moonbitstack/moonasgi\",\n}\n",
  )
  let api = file_at(files, "greet/greet.api")
  assert_eq(contains(api, "service greet {"), true)
  let app = file_at(files, "greet/src/app.mbt")
  // the generated app uses the 0.10.5-safe arrow-closure route registration
  assert_eq(contains(app, "pub fn build_app() -> @moonapi.App"), true)
  assert_eq(contains(app, "ctx => ping(ctx)"), true)
  assert_eq(contains(app, "DO NOT EDIT"), true)
  assert_eq(file_at(files, "greet/README.md") != "", true)
}

///|
test "scaffold_rpc emits a moonrpc project tree" {
  let files = scaffold_rpc("echo")
  assert_eq(files.length(), 5)
  assert_eq(
    contains(file_at(files, "echo/moon.mod"), pinned("moonbitstack/moonrpc")),
    true,
  )
  let proto = file_at(files, "echo/echo.proto")
  assert_eq(contains(proto, "service Echo {"), true)
  assert_eq(contains(proto, "rpc Ping(PingReq) returns (PingResp);"), true)
  let stub = file_at(files, "echo/src/service.mbt")
  assert_eq(contains(stub, "@moonrpc.Method"), true)
}

///|
test "scaffold_model emits a moonorm project tree" {
  let files = scaffold_model("account")
  assert_eq(files.length(), 5)
  let m = file_at(files, "account/moon.mod")
  assert_eq(contains(m, pinned("moonbitstack/moonorm")), true)
  assert_eq(contains(m, pinned("moonbitstack/moondb")), true)
  let sql = file_at(files, "account/schema.sql")
  assert_eq(contains(sql, "CREATE TABLE account"), true)
  let model = file_at(files, "account/src/model.mbt")
  assert_eq(contains(model, "account_model : @moonorm.Model[Account]"), true)
  assert_eq(contains(model, "pub fn account_insert("), true)
}

///|
test "scaffold_docker emits a two-stage Dockerfile and dockerignore" {
  let files = scaffold_docker("greet", port=9000)
  assert_eq(files.length(), 2)
  let df = file_at(files, "Dockerfile")
  assert_eq(contains(df, "FROM debian:stable-slim AS build"), true)
  assert_eq(contains(df, "moon build --target native --release"), true)
  assert_eq(contains(df, "EXPOSE 9000"), true)
  assert_eq(contains(df, "ENTRYPOINT [\"/app/greet\"]"), true)
  assert_eq(contains(file_at(files, ".dockerignore"), "target/"), true)
}

///|
test "scaffold_kube emits a deployment and a service" {
  let files = scaffold_kube("greet", port=9000, replicas=3)
  assert_eq(files.length(), 2)
  let dep = file_at(files, "deploy/deployment.yaml")
  assert_eq(contains(dep, "kind: Deployment"), true)
  assert_eq(contains(dep, "replicas: 3"), true)
  assert_eq(contains(dep, "containerPort: 9000"), true)
  assert_eq(contains(dep, "path: /ping"), true)
  let svc = file_at(files, "deploy/service.yaml")
  assert_eq(contains(svc, "kind: Service"), true)
  assert_eq(contains(svc, "targetPort: 9000"), true)
}

///|
/// The reason the manifests are built as values rather than joined out of
/// strings: a name that carries a character YAML gives a meaning to.
///
/// Joined, the colon in `a: b` would open a mapping in the middle of a value and
/// the file would parse as something else entirely — silently, because it would
/// still be valid YAML.
test "a name that would have broken a string-joining generator" {
  let files = scaffold_kube("a: b", port=12000)
  let dep = file_at(files, "deploy/deployment.yaml")
  // The name is quoted, so it stays one value.
  assert_eq(contains(dep, "\"a: b\""), true)
  // And the document still reads back as the document that was built.
  let back = @moonyaml.loads(dep[:])
  let meta = match back {
    Object(members) => members.get("metadata")
    _ => None
  }
  let name = match meta {
    Some(Object(members)) => members.get("name")
    _ => None
  }
  assert_eq(name, Some(Json::string("a: b")))
}

///|
/// A generated manifest is a document, so it reads back as one — which a
/// hand-joined string was never checked against.
test "the generated manifests are documents" {
  let files = scaffold_kube("greet")
  let dep = @moonyaml.loads(file_at(files, "deploy/deployment.yaml")[:])
  assert_eq(down(dep, ["spec", "replicas"][:]), Some(Json::number(2)))
  assert_eq(
    down(
      dep,
      [
        "spec", "template", "spec", "containers", "0", "ports", "0", "containerPort",
      ][:],
    ),
    Some(Json::number(port.to_double())),
  )
  let svc = @moonyaml.loads(file_at(files, "deploy/service.yaml")[:])
  assert_eq(
    down(svc, ["spec", "ports", "0", "targetPort"][:]),
    Some(Json::number(port.to_double())),
  )
  assert_eq(down(svc, ["spec", "type"][:]), Some(Json::string("ClusterIP")))
  // The house port, so a generated manifest and a generated config agree.
  assert_eq(port, 12000)
}
