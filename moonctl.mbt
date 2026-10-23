// The surface moonctl had before it was split into packages, re-exported from
// where each name now lives, so `@moonctl.parse` and the rest keep working.

///|
pub using @template {
  type FuncFn,
  type Template,
  type TemplateError,
  type Value,
  render,
}

///|
pub using @style {type Style, type StyleError}

///|
pub using @api {
  type Bind,
  type Field,
  type Group,
  type Range,
  type Route,
  type Spec,
  type SpecError,
  type TypeDef,
  deps,
  parse,
  parse_all,
  parse_lenient,
  resolve_import,
}

///|
pub using @gen {generate, generate_with, spec_to_value}

///|
pub using @proto {
  type Proto,
  type ProtoEnum,
  type ProtoEnumValue,
  type Label,
  type ProtoField,
  type ProtoMessage,
  type ProtoOneof,
  type ProtoService,
  type Rpc,
  generate_grpc,
  parse_proto,
  proto_reserved_conflicts,
}

///|
pub using @doc {
  type DocVersion,
  generate_doc,
  openapi_document,
  swagger_ui_stub,
}

///|
pub using @gql {generate_gql}

///|
pub using @model {
  type DataSource,
  type DataSourceError,
  type DdlColumn,
  type DdlTable,
  type PgTarget,
  type ReflectedColumn,
  generate_crud,
  generate_crud_from_ddl,
  generate_crud_from_reflection,
  generate_model,
  parse_ddl,
  parse_dsn,
  tables_from_reflection,
}

///|
pub using @plugin {
  type GenFile,
  type Plugin,
  gen_files_to_json,
  parse_gen_files,
  plugin_argv,
  plugin_from_json,
  plugin_request,
  spec_from_json,
  spec_to_json,
}

///|
pub using @agent {generate_agent}

///|
pub using @scaffold {
  type Regen,
  type TreeFile,
  generate_gql_tree,
  generate_rpc_tree,
  generate_tree,
  pins,
  port,
  scaffold_api,
  scaffold_docker,
  scaffold_gql,
  scaffold_kube,
  scaffold_model,
  scaffold_rpc,
  tree_plan,
}
