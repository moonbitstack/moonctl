# Examples

A runnable tour of the public `@moonctl` codegen API — the same pipeline the
`mctl` binary runs, called as a library. Each example inlines its `.api` /
`.proto` / `.sql` source as a string, runs the generator in-process, and prints
the artefact, so every one runs without file IO and on every backend (unlike the
native `mctl` binary).

```bash
moon run examples/00-greet
```

| # | Example | What it shows | Key API |
| --- | --- | --- | --- |
| 00 | [`greet`](00-greet/) | Legacy inline `.api` → moonapi scaffold + OpenAPI 3.1 document | `parse`, `generate`, `openapi_document` |
| 01 | [`modern-api`](01-modern-api/) | Modern `.api` dialect: `info (…)`, `@doc`/`@handler`, `verb /path (Req) returns (Resp)` | `parse` (typed routes, `Spec::info`), `generate` |
| 02 | [`openapi-versions`](02-openapi-versions/) | One spec, three dialects: Swagger 2.0 / OpenAPI 3.0 / 3.1 + a Swagger UI page | `generate_doc`, `DocVersion`, `swagger_ui_stub` |
| 03 | [`proto-grpc`](03-proto-grpc/) | `.proto` → moonrpc: messages (`repeated`/`map`/`oneof`/`reserved`), enums, streaming RPCs | `parse_proto`, `generate_grpc`, `proto_reserved_conflicts` |
| 04 | [`model`](04-model/) | `.api` `type` → moonorm model + `Table` + up/down migration | `generate_model` |
| 05 | [`ddl-crud`](05-ddl-crud/) | SQL DDL → moonorm model + parameterised typed CRUD | `parse_ddl`, `generate_crud_from_ddl` |
| 06 | [`datasource`](06-datasource/) | Live-datasource reflection core: DSN parse + reflected columns → CRUD | `parse_dsn`, `tables_from_reflection`, `generate_crud_from_reflection` |
| 07 | [`scaffold`](07-scaffold/) | Whole-project trees: `api`/`rpc`/`model new`, `docker`, `kube` | `scaffold_api`/`scaffold_rpc`/`scaffold_model`/`scaffold_docker`/`scaffold_kube`, `GenFile` |
| 08 | [`plugin`](08-plugin/) | Out-of-tree plugin protocol round-trip over stdio JSON — goctl's `{Api, ApiFilePath, Style, Dir}` request | `plugin_request`, `plugin_from_json`, `gen_files_to_json`, `parse_gen_files` |
| 09 | [`template`](09-template/) | Runtime template engine (`text/template`): interpolation, `range`/`if`, pipelines, a custom `func`, and spec-driven codegen | `render`, `Template`, `Value`, `spec_to_value`, `generate_with`, `generate(template=)` |
| 10 | [`agent`](10-agent/) | `.api` → moonkoog agent: one `Tool` per route, assembled into an `AIAgent` | `generate_agent` |
| 11 | [`gql`](11-gql/) | `.api` `type` → moongql code-first schema + resolver stubs | `generate_gql` |
| 12 | [`tags`](12-tags/) | Struct tags → where a field binds from (`json`/`form`/`path`/`header`), the name it binds under, and the `optional`/`default=`/`options=`/`range=` that constrain it | `Field::bind`, `Field::json_name`, `Field::default_`, `openapi_document` |
| 13 | [`tree`](13-tree/) | Multi-file `import`, the `--style` naming template, the layered project tree, and what a second run rewrites | `deps`, `parse_all`, `Style::parse`, `generate_tree`, `tree_plan` |

Each `main.mbt` calls the real API and prints the actual generated artefact — a
moonapi scaffold, an OpenAPI document, moonorm SQL/CRUD, a moonrpc gRPC stub,
plugin JSON, a rendered template — so running it proves the feature works. The
whole set is verified under `moon check --target all --deny-warn`,
`moon build --target all`, and `moon run … --target native`.
