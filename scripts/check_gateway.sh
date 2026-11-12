#!/usr/bin/env bash
# The generated gateway answers requests, and is `moon fmt`-clean.
#
#   scripts/check_gateway.sh [path-to-mctl]
#
# Unit tests can only compare the generated file as text. What the matcher and the
# parameter binding actually do is only visible once the file is compiled and
# driven, so this script generates a gateway over a route map that names path
# parameters, compiles it against the published releases, and calls it through the
# `Caller` port:
#
#   - a parameter binds into the request document, and beats a body member;
#   - a literal segment beats a parameter, whatever the declaration order;
#   - a parameter on a body that is not an object is a 400, a blank body is `{}`;
#   - 404, 400 and 502 come back for the three failures;
#   - `moon fmt` leaves the generated file alone;
#   - two routes of one shape are refused, and nothing is written.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mctl="${1:-$here/_build/native/debug/build/cmd/mctl/mctl.exe}"
if [[ ! -x "$mctl" ]]; then
  echo "no mctl at $mctl; build it first (moon build --target native)" >&2
  exit 2
fi
mctl="$(cd "$(dirname "$mctl")" && pwd)/$(basename "$mctl")"

# The generated file reads bodies with the family's parser, so the project has to
# carry it at the version this repository pins; reading moon.mod keeps the two from
# drifting apart.
pin="$(sed -n 's/.*"moonbitstack\/moonjson@\([^"]*\)".*/\1/p' "$here/moon.mod")"
if [[ -z "$pin" ]]; then
  echo "no moonbitstack/moonjson pin in moon.mod" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

printf '%s\n' \
  'name = "probe/gateway"' \
  '' \
  'version = "0.0.1"' \
  '' \
  'import {' \
  "  \"moonbitstack/moonjson@$pin\"," \
  '}' >moon.mod

printf '%s\n' 'import {' '  "moonbitstack/moonjson/json",' '}' >moon.pkg

cat >shop.proto <<'PROTO'
syntax = "proto3";

package shop;

message GetReq { string id = 1; }
message User { string id = 1; string name = 2; }

service UserService {
  rpc Get(GetReq) returns (User);
  rpc Me(GetReq) returns (User);
  rpc Create(GetReq) returns (User);
}
PROTO

cat >shop.routes <<'ROUTES'
# what a browser sees      what the RPC is called
get  /v1/users/:id        /shop.UserService/Get
get  /v1/users/me         /shop.UserService/Me
post /v1/users            /shop.UserService/Create
ROUTES

"$mctl" gateway shop.proto

cat >gateway_check_wbtest.mbt <<'TEST'
///|
fn member_of(body : Json, name : String) -> String {
  match body {
    Object(members) =>
      match members.get(name) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
/// A gateway over a `Caller` that records what it was asked and answers `{}`.
fn recorder(calls : Array[(String, Json)]) -> Gateway {
  Gateway::new({
    call: (rpc, body) => {
      calls.push((rpc, body))
      Json((Map([]) : Map[String, Json]))
    },
  })
}

///|
test "a parameter binds into the request document, and beats the body" {
  let calls : Array[(String, Json)] = []
  let reply = recorder(calls).handle_text(
    "GET", "/v1/users/42", "{\"name\": \"ada\", \"id\": \"from the body\"}",
  )
  assert_eq(reply.status, 200)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "/shop.UserService/Get")
  // the path is where the client said which resource it means
  assert_eq(member_of(calls[0].1, "id"), "42")
  assert_eq(member_of(calls[0].1, "name"), "ada")
}

///|
test "a literal segment beats a parameter, whatever the order" {
  let calls : Array[(String, Json)] = []
  let _ = recorder(calls).handle_text("GET", "/v1/users/me", "{}")
  assert_eq(calls[0].0, "/shop.UserService/Me")
  assert_eq(method_of("GET", "/v1/users/me"), "/shop.UserService/Me")
  assert_eq(method_of("GET", "/v1/users/7"), "/shop.UserService/Get")
  assert_eq(method_of("DELETE", "/v1/users/7"), "")
}

///|
test "a trailing slash and a doubled one are the same path" {
  let calls : Array[(String, Json)] = []
  let _ = recorder(calls).handle_text("GET", "/v1/users/7/", "")
  let _ = recorder(calls).handle_text("GET", "/v1//users/7", "")
  assert_eq(calls.length(), 2)
  assert_eq(member_of(calls[0].1, "id"), "7")
  assert_eq(member_of(calls[1].1, "id"), "7")
}

///|
test "a blank body is the empty document" {
  let calls : Array[(String, Json)] = []
  let reply = recorder(calls).handle_text("GET", "/v1/users/7", "  \n\t")
  assert_eq(reply.status, 200)
  assert_eq(member_of(calls[0].1, "id"), "7")
}

///|
test "a parameter with nowhere to land is a 400" {
  let calls : Array[(String, Json)] = []
  let reply = recorder(calls).handle_text("GET", "/v1/users/7", "[7]")
  assert_eq(reply.status, 400)
  assert_eq(calls.length(), 0)
  assert_eq(
    match reply.body {
      Object(members) =>
        match members.get("error") {
          Some(String(why)) => why
          _ => ""
        }
      _ => ""
    },
    "a path parameter needs a JSON object body",
  )
}

///|
test "the four answers" {
  let calls : Array[(String, Json)] = []
  let gw = recorder(calls)
  assert_eq(gw.handle_text("POST", "/v1/users", "{}").status, 200)
  assert_eq(gw.handle_text("POST", "/v1/users", "{oops").status, 400)
  assert_eq(gw.handle_text("POST", "/v1/users/7", "{}").status, 404)
  let failing = Gateway::new({
    call: (_rpc, _body) => raise GatewayUpstream(status=503, message="down"),
  })
  let reply = failing.handle_text("POST", "/v1/users", "{}")
  assert_eq(reply.status, 502)
  assert_eq(member_of(reply.body, "error"), "upstream 503: down")
}
TEST

# What mctl writes is what `moon fmt` would write. Byte comparison, not line
# endings: a Windows checkout would otherwise report every file as changed.
git init -q .
git config core.autocrlf false
git config core.safecrlf false
printf '* -text\n' >.gitattributes
printf '_build/\n.mooncakes/\n' >.gitignore
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -qm generated
moon fmt >/dev/null
if ! git diff --quiet; then
  echo "the generated gateway is not moon fmt-clean:" >&2
  git --no-pager diff --stat >&2
  exit 1
fi
echo "ok   the generated gateway is moon fmt-clean"

moon test --target native

# A table with two routes of one shape has a route nothing can reach, so the
# generator refuses it instead of writing a table with a dead line.
mkdir clash
cp shop.proto clash/clash.proto
cat >clash/clash.routes <<'ROUTES'
get /v1/users/:id   /shop.UserService/Get
get /v1/users/:name /shop.UserService/Me
ROUTES
set +e
out="$(cd clash && "$mctl" gateway clash.proto 2>&1)"
set -e
if [[ -f clash/clash_gateway.mbt ]]; then
  echo "a route map with two routes of one shape was written anyway" >&2
  exit 1
fi
case "$out" in
  *"answers the same requests as"*) ;;
  *)
    echo "the clash was not reported: $out" >&2
    exit 1
    ;;
esac
echo "ok   two routes of one shape are refused"
