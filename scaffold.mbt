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
/// A `moon.mod.json` for a scaffolded project with the given dependency map (each
/// entry a `"pkg": "version"` line).
fn mod_json(name : String, deps : Array[(String, String)]) -> String {
  let dep_lines : Array[String] = []
  for d in deps {
    dep_lines.push("    " + quote(d.0) + ": " + quote(d.1))
  }
  let deps_body = if dep_lines.length() == 0 {
    "{}"
  } else {
    "{\n" + join_commas(dep_lines) + "\n  }"
  }
  "{\n  \"name\": " +
  quote(name) +
  ",\n  \"version\": \"0.1.0\",\n  \"deps\": " +
  deps_body +
  "\n}\n"
}

///|
/// A `src/moon.pkg.json` importing the given packages, and marked native+executable
/// when `executable` (a runnable service needs the async server, which is native).
fn pkg_json(imports : Array[String], executable : Bool) -> String {
  let import_lines : Array[String] = []
  for im in imports {
    import_lines.push("    " + quote(im))
  }
  let imports_body = if import_lines.length() == 0 {
    "[]"
  } else {
    "[\n" + join_commas(import_lines) + "\n  ]"
  }
  let mut out = "{\n  \"import\": " + imports_body
  if executable {
    out = out + ",\n  \"is-main\": true,\n  \"supported-targets\": [\"native\"]"
  }
  out + "\n}\n"
}

///|
/// Join lines with `,\n` — the JSON-array/object element separator.
fn join_commas(parts : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + ",\n"
    }
    out = out + parts[i]
  }
  out
}

///|
/// Scaffold a runnable moonapi service project under `<name>/`: a `moon.mod.json`
/// (depending on the published `moonapi` + `moonasgi`), a sample `<name>.api` spec,
/// its generated routes+handlers in `src/app.mbt` (through the same `generate` the
/// `gen api` command uses, so it compiles), and a README. This is goctl's
/// `goctl api new`.
pub fn scaffold_api(name : String) -> Array[GenFile] {
  let api = sample_api(name)
  let app = generate_builtin(parse_lenient(api))
  [
    {
      path: name + "/moon.mod.json",
      content: mod_json(name, [
        ("moonbitstack/moonapi", "0.6.0"),
        ("moonbitstack/moonasgi", "0.1.0"),
      ]),
    },
    { path: name + "/" + name + ".api", content: api, },
    {
      path: name + "/src/moon.pkg.json",
      content: pkg_json(
        ["moonbitstack/moonapi", "moonbitstack/moonasgi"],
        false,
      ),
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
/// Scaffold a moonrpc service project under `<name>/`: a `moon.mod.json` (depending
/// on the published `moonrpc`), a sample `<name>.proto`, its generated service stub
/// in `src/service.mbt` (through the same `generate_grpc` as `gen proto`), and a
/// README. goctl's `goctl rpc new`.
pub fn scaffold_rpc(name : String) -> Array[GenFile] {
  let proto = sample_proto(name)
  let stub = generate_grpc(parse_proto(proto))
  [
    {
      path: name + "/moon.mod.json",
      content: mod_json(name, [("moonbitstack/moonrpc", "0.6.0")]),
    },
    { path: name + "/" + name + ".proto", content: proto, },
    {
      path: name + "/src/moon.pkg.json",
      content: pkg_json(["moonbitstack/moonrpc"], false),
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
/// Scaffold a moonorm data-layer project under `<name>/`: a `moon.mod.json`
/// (depending on the published `moonorm` + `moondb`), a sample `schema.sql`, its
/// generated models + CRUD in `src/model.mbt` (through the same
/// `generate_crud_from_ddl` as `gen crud`), and a README. goctl's `goctl model … new`.
pub fn scaffold_model(name : String) -> Array[GenFile] {
  let sql = sample_sql(name)
  let model = generate_crud_from_ddl(sql)
  [
    {
      path: name + "/moon.mod.json",
      content: mod_json(name, [
        ("moonbitstack/moonorm", "0.6.1"),
        ("moonbitstack/moondb", "0.1.3"),
      ]),
    },
    { path: name + "/schema.sql", content: sql, },
    {
      path: name + "/src/moon.pkg.json",
      content: pkg_json(["moonbitstack/moonorm", "moonbitstack/moondb"], false),
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
pub fn scaffold_docker(name : String, port? : Int = 8080) -> Array[GenFile] {
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
/// Scaffold a Kubernetes deployment for the service under `deploy/`: a `Deployment`
/// (`replicas` pods of the `<name>` image, a container port, and a liveness probe on
/// `/ping`) and a `Service` exposing it. goctl's `goctl kube deploy`.
pub fn scaffold_kube(
  name : String,
  port? : Int = 8080,
  replicas? : Int = 2,
) -> Array[GenFile] {
  let p = port.to_string()
  let r = replicas.to_string()
  let deployment = "apiVersion: apps/v1\n" +
    "kind: Deployment\n" +
    "metadata:\n  name: " +
    name +
    "\n  labels:\n    app: " +
    name +
    "\nspec:\n  replicas: " +
    r +
    "\n  selector:\n    matchLabels:\n      app: " +
    name +
    "\n  template:\n    metadata:\n      labels:\n        app: " +
    name +
    "\n    spec:\n      containers:\n        - name: " +
    name +
    "\n          image: " +
    name +
    ":latest\n          ports:\n            - containerPort: " +
    p +
    "\n          livenessProbe:\n            httpGet:\n              path: /ping\n              port: " +
    p +
    "\n            initialDelaySeconds: 5\n            periodSeconds: 10\n"
  let service = "apiVersion: v1\n" +
    "kind: Service\n" +
    "metadata:\n  name: " +
    name +
    "\nspec:\n  selector:\n    app: " +
    name +
    "\n  ports:\n    - protocol: TCP\n      port: 80\n      targetPort: " +
    p +
    "\n  type: ClusterIP\n"
  [
    { path: "deploy/deployment.yaml", content: deployment, },
    { path: "deploy/service.yaml", content: service, },
  ]
}
