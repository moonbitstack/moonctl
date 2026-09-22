// Project skeletons: `mctl api/rpc/model new <name>`, `mctl docker`, `mctl kube`.
// goctl scaffolds a whole nested project tree (a runnable service, its config, a
// Dockerfile, a Kubernetes deployment) rather than a single file; these generators
// are the MoonBit equivalent. Each returns the list of files to write — reusing the
// `GenFile { path, content }` shape the plugin protocol already uses — so the `mctl`
// binary writes them with the same nested-directory `mkdir -p` walk. The `api`, `rpc`
// and `model` skeletons emit their source through the very same built-in generators
// (`generate` / `generate_grpc` / `generate_crud_from_ddl`), so a scaffolded project
// compiles for the same reason a generated file does.

///|
/// A sample `.api` spec seeded into an `api` skeleton.
fn sample_api(name : String) -> String {
  "// " +
  name +
  " service — edit this spec, then regenerate with `mctl gen api " +
  name +
  ".api`.\nservice " +
  name +
  " {\n  get  /ping        ping        \"health check\"\n  get  /" +
  name +
  "/:id   get_one\n  post /" +
  name +
  "        create_one  \"create one\"\n}\n\ntype CreateReq {\n  name: string\n  age:  int\n}\n"
}

///|
/// A sample `.proto` seeded into an `rpc` skeleton.
fn sample_proto(name : String) -> String {
  "syntax = \"proto3\";\n\npackage " +
  name +
  ";\n\nmessage PingReq {}\n\nmessage PingResp {\n  string message = 1;\n}\n\nservice " +
  to_pascal(name) +
  " {\n  rpc Ping(PingReq) returns (PingResp);\n}\n"
}

///|
/// A sample SQL schema seeded into a `model` skeleton.
fn sample_sql(name : String) -> String {
  "-- " +
  name +
  " schema — edit, then regenerate with `mctl gen crud schema.sql`.\nCREATE TABLE " +
  name +
  " (\n  id    INTEGER PRIMARY KEY,\n  name  TEXT NOT NULL,\n  age   INTEGER\n);\n"
}

///|
/// Scaffold a runnable moonapi service project under `<name>/`: a `moon.mod`
/// (depending on the published `moonapi` + `moonasgi`), a sample `<name>.api` spec,
/// its generated routes+handlers in `src/app.mbt` (through the same `generate` the
/// `gen api` command uses, so it compiles), and a README. This is goctl's
/// `goctl api new`.
pub fn scaffold_api(name : String) -> Array[GenFile] {
  let api = sample_api(name)
  let app = generate_builtin(parse_lenient(api))
  [
    {
      path: name + "/moon.mod",
      content: mod_file(name, ["moonbitstack/moonapi", "moonbitstack/moonasgi"]),
    },
    { path: name + "/" + name + ".api", content: api, },
    {
      path: name + "/src/moon.pkg",
      content: pkg_file([
        ("moonbitstack/moonapi", ""),
        ("moonbitstack/moonasgi", ""),
      ]),
    },
    { path: name + "/src/app.mbt", content: app, },
    {
      path: name + "/README.md",
      content: "# " +
      name +
      "\n\nA moonapi service scaffolded by `mctl api new`. Edit `" +
      name +
      ".api`, regenerate with `mctl gen api " +
      name +
      ".api`, and fill in the handler stubs in `src/app.mbt`.\n",
    },
  ]
}

///|
/// Scaffold a moonrpc service project under `<name>/`: a `moon.mod` (depending
/// on the published `moonrpc`), a sample `<name>.proto`, its generated service stub
/// in `src/service.mbt` (through the same `generate_grpc` as `gen proto`), and a
/// README. goctl's `goctl rpc new`.
pub fn scaffold_rpc(name : String) -> Array[GenFile] {
  let proto = sample_proto(name)
  let stub = generate_grpc(parse_proto(proto))
  [
    {
      path: name + "/moon.mod",
      content: mod_file(name, ["moonbitstack/moonrpc"]),
    },
    { path: name + "/" + name + ".proto", content: proto, },
    {
      path: name + "/src/moon.pkg",
      content: pkg_file([("moonbitstack/moonrpc", "")]),
    },
    { path: name + "/src/service.mbt", content: stub, },
    {
      path: name + "/README.md",
      content: "# " +
      name +
      "\n\nA moonrpc service scaffolded by `mctl rpc new`. Edit `" +
      name +
      ".proto`, regenerate with `mctl gen proto " +
      name +
      ".proto`, and implement the RPC handlers in `src/service.mbt`.\n",
    },
  ]
}

///|
/// Scaffold a moonorm data-layer project under `<name>/`: a `moon.mod`
/// (depending on the published `moonorm` + `moondb`), a sample `schema.sql`, its
/// generated models + CRUD in `src/model.mbt` (through the same
/// `generate_crud_from_ddl` as `gen crud`), and a README. goctl's `goctl model … new`.
pub fn scaffold_model(name : String) -> Array[GenFile] {
  let sql = sample_sql(name)
  let model = generate_crud_from_ddl(sql)
  [
    {
      path: name + "/moon.mod",
      content: mod_file(name, ["moonbitstack/moonorm", "moonbitstack/moondb"]),
    },
    { path: name + "/schema.sql", content: sql, },
    {
      path: name + "/src/moon.pkg",
      content: pkg_file([
        ("moonbitstack/moonorm", ""),
        ("moonbitstack/moondb", ""),
      ]),
    },
    { path: name + "/src/model.mbt", content: model, },
    {
      path: name + "/README.md",
      content: "# " +
      name +
      "\n\nA moonorm data layer scaffolded by `mctl model new`. Edit `schema.sql`, regenerate with `mctl gen crud schema.sql`.\n",
    },
  ]
}

///|
/// Scaffold container files for a native `mctl`-generated service: a `Dockerfile`
/// (a MoonBit build stage that produces the native binary, then a slim runtime
/// stage that runs it) and a `.dockerignore`. `name` is the binary/image name,
/// `port` the port the service listens on. goctl's `goctl docker`.
pub fn scaffold_docker(name : String, port? : Int = port) -> Array[GenFile] {
  let p = port.to_string()
  let dockerfile = "# syntax=docker/dockerfile:1\n" +
    "# Build stage: compile the native mctl-generated service.\n" +
    "FROM debian:stable-slim AS build\n" +
    "RUN apt-get update && apt-get install -y curl build-essential && rm -rf /var/lib/apt/lists/*\n" +
    "RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash\n" +
    "ENV PATH=/root/.moon/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" +
    "WORKDIR /src\n" +
    "COPY . .\n" +
    "RUN moon build --target native --release\n" +
    "\n# Runtime stage: carry only the built binary.\n" +
    "FROM debian:stable-slim\n" +
    "WORKDIR /app\n" +
    "COPY --from=build /src/target/native/release/build/" +
    name +
    "/" +
    name +
    ".exe /app/" +
    name +
    "\n" +
    "EXPOSE " +
    p +
    "\n" +
    "ENTRYPOINT [\"/app/" +
    name +
    "\"]\n"
  let dockerignore = "_build/\ntarget/\n.mooncakes/\n.git/\n*.md\n"
  [
    { path: "Dockerfile", content: dockerfile, },
    { path: ".dockerignore", content: dockerignore, },
  ]
}

///|
/// The port a scaffolded service listens on.
///
/// 12000, the one every server in this family defaults to: HTTP, WebSocket and
/// h2c share it because one listener tells them apart, so a generated manifest
/// and a generated configuration name the same number without anyone saying
/// which they meant.
pub let port : Int = 12000

///|
/// Scaffold a Kubernetes deployment for the service under `deploy/`: a
/// `Deployment` (`replicas` pods of the `<name>` image, a container port, and a
/// liveness probe on `/ping`) and a `Service` exposing it. goctl's
/// `goctl kube deploy`.
///
/// The manifests are built as values and written by `moonyaml`, not joined
/// out of string fragments. A generator that joins fragments has the indentation
/// in its string literals, where a missed space is invisible, and quotes nothing
/// — so the first service name with a colon in it emits a file Kubernetes reads
/// as something else.
pub fn scaffold_kube(
  name : String,
  port? : Int = port,
  replicas? : Int = 2,
) -> Array[GenFile] {
  let labels = Json::object({ "app": Json::string(name) })
  let deployment = Json::object({
    "apiVersion": Json::string("apps/v1"),
    "kind": Json::string("Deployment"),
    "metadata": Json::object({ "name": Json::string(name), "labels": labels }),
    "spec": Json::object({
      "replicas": Json::number(replicas.to_double()),
      "selector": Json::object({ "matchLabels": labels }),
      "template": Json::object({
        "metadata": Json::object({ "labels": labels }),
        "spec": Json::object({
          "containers": Json::array([
            Json::object({
              "name": Json::string(name),
              "image": Json::string(name + ":latest"),
              "ports": Json::array([
                Json::object({ "containerPort": Json::number(port.to_double()) }),
              ]),
              "livenessProbe": Json::object({
                "httpGet": Json::object({
                  "path": Json::string("/ping"),
                  "port": Json::number(port.to_double()),
                }),
                "initialDelaySeconds": Json::number(5),
                "periodSeconds": Json::number(10),
              }),
            }),
          ]),
        }),
      }),
    }),
  })
  let service = Json::object({
    "apiVersion": Json::string("v1"),
    "kind": Json::string("Service"),
    "metadata": Json::object({ "name": Json::string(name) }),
    "spec": Json::object({
      "selector": labels,
      "ports": Json::array([
        Json::object({
          "protocol": Json::string("TCP"),
          "port": Json::number(80),
          "targetPort": Json::number(port.to_double()),
        }),
      ]),
      "type": Json::string("ClusterIP"),
    }),
  })
  [
    { path: "deploy/deployment.yaml", content: @moonyaml.dumps(deployment), },
    { path: "deploy/service.yaml", content: @moonyaml.dumps(service), },
  ]
}
