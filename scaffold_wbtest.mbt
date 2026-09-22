///|
/// The content of the file at `path` among `files`, or `""` if none matches.
fn file_at(files : Array[GenFile], path : String) -> String {
  for f in files {
    if f.path == path {
      return f.content
    }
  }
  ""
}

///|
/// How `moon.mod` writes an import of `dep` at its pin.
fn pinned(dep : String) -> String {
  "\"" + dep + "@" + pins.get(dep).unwrap() + "\""
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
