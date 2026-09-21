name = "moonbitstack/moonctl"

version = "0.8.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonctl"

license = "Apache-2.0"

keywords = [
  "goctl",
  "codegen",
  "scaffold",
  "api",
  "moonapi",
  "moonbit",
  "cli",
]

description = "moonctl (mctl) — a spec-driven code generator for MoonBit (← goctl): parse a .api service spec and emit compilable moonapi scaffolding (routes + handler stubs)."

import {
  "moonbitlang/async@0.20.3",
  "moonbitstack/moonjson@0.3.0",
  "moonbitstack/moondb@0.1.8",
  "moonbitstack/moonsqlite@0.3.0",
  "moonbitstack/moonpostgres@0.4.0",
}
