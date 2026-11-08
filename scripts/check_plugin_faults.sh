#!/usr/bin/env bash
# The plugin spawn path, driven with real processes.
#
# The unit tests cover the protocol's decisions — `safe_path`, `plugin_plan`,
# `parse_gen_files` — but not the half that cannot be tested without a process: the
# arguments that reach the plugin, the request on its stdin, the exit code that
# decides whether the reply is read at all, and the temporary file the request was
# written through. Every one of those is a line whose removal would leave the unit
# tests green, so each is exercised here with a plugin that misbehaves in exactly
# one way.
#
# Usage: scripts/check_plugin_faults.sh [path/to/mctl]
set -euo pipefail

mctl="${1:-$PWD/_build/native/debug/build/cmd/mctl/mctl.exe}"
if [ ! -x "$mctl" ]; then
  echo "no mctl at $mctl — build it first (moon build --target native)" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

fail() {
  echo "plugin faults: $*" >&2
  echo "--- last run ---" >&2
  cat run.txt >&2 2>/dev/null || true
  exit 1
}

cat > spec.api <<'API'
type PingReq {
  name: string
}

type PingResp {
  message: string
}

service greet {
  @handler ping
  post /ping (PingReq) returns (PingResp)
}
API

# 1. The invocation's arguments reach the plugin, and the request reaches its
#    stdin: the plugin records both, and answers with one file.
cat > ok.sh <<'SH'
#!/bin/sh
set -e
cat > seen-request.json
printf '%s\n' "$@" > seen-args.txt
printf '%s' '{"files": [{"path": "written/one.mbt", "content": "// one\n"}]}'
SH
chmod +x ok.sh
"$mctl" plugin "./ok.sh -flag value" spec.api > run.txt 2>&1 || fail "a working plugin did not run"

[ -f written/one.mbt ] || fail "the plugin's file was not written"
[ "$(cat written/one.mbt)" = "// one" ] || fail "the file was written with the wrong content"
# the whole invocation after the program is the plugin's argv
[ "$(sed -n '1p' seen-args.txt)" = "-flag" ] || fail "the plugin did not get -flag"
[ "$(sed -n '2p' seen-args.txt)" = "value" ] || fail "the plugin did not get value"
# and the request is goctl's four keys
grep -q '"Api"' seen-request.json || fail "the request has no Api"
grep -q '"ApiFilePath": "spec.api"' seen-request.json || fail "the request does not name the file"
grep -q '"Style": "gozero"' seen-request.json || fail "the request does not carry the style"
grep -q '"Dir": ""' seen-request.json || fail "the request does not carry the output directory"
grep -q '"service": "greet"' seen-request.json || fail "the request does not carry the parsed spec"
# the request travels through a temporary file, and that file is gone afterwards
[ ! -f spec.api.mctlreq.json ] || fail "the temporary request file was left behind"

# 2. A plugin that fails must not have its reply written: the exit code is what
#    decides, not the presence of files on its stdout.
cat > failing.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' '{"files": [{"path": "written/from-failure.mbt", "content": "// no\n"}]}'
exit 3
SH
chmod +x failing.sh
"$mctl" plugin ./failing.sh spec.api > run.txt 2>&1 || true
[ ! -f written/from-failure.mbt ] || fail "a plugin that exited 3 had its files written"
grep -q "exited with code 3" run.txt || fail "the exit code was not reported"

# 3. A path outside the output directory is refused, and named.
cat > escape.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' '{"files": [{"path": "../escaped.mbt", "content": "// no\n"}]}'
SH
chmod +x escape.sh
"$mctl" plugin ./escape.sh spec.api > run.txt 2>&1 || true
[ ! -f ../escaped.mbt ] || fail "a plugin wrote outside the output directory"
grep -q "refused ../escaped.mbt" run.txt || fail "the refused path was not reported"

# 4. A path claimed twice is written once, and the second copy refused.
cat > twice.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' '{"files": [{"path": "written/twice.mbt", "content": "first"}, {"path": "written/twice.mbt", "content": "second"}]}'
SH
chmod +x twice.sh
"$mctl" plugin ./twice.sh spec.api > run.txt 2>&1 || true
[ "$(cat written/twice.mbt)" = "first" ] || fail "the first copy of a duplicate path did not win"
grep -q "the plugin wrote it twice" run.txt || fail "the duplicate was not reported"

# 5. A reply that is not the protocol's shape writes nothing and says so.
cat > garbage.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' 'this is not json'
SH
chmod +x garbage.sh
"$mctl" plugin ./garbage.sh spec.api > run.txt 2>&1 || true
grep -q "plugin error" run.txt || fail "a reply that is not JSON was not reported"
[ ! -f written/garbage.mbt ] || fail "a reply that is not JSON wrote a file"

# 6. A nested path has its directories created, and one level of them is enough.
cat > nested.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' '{"files": [{"path": "deep/a/b/three.mbt", "content": "// three\n"}]}'
SH
chmod +x nested.sh
"$mctl" plugin ./nested.sh spec.api > run.txt 2>&1 || true
[ -f deep/a/b/three.mbt ] || fail "a nested path was not created"

# 7. A plugin that produces nothing is a run that writes nothing, and does not
#    fail: an out-of-tree generator may legitimately have nothing to say.
cat > silent.sh <<'SH'
#!/bin/sh
cat > /dev/null
printf '%s' '{"files": []}'
SH
chmod +x silent.sh
"$mctl" plugin ./silent.sh spec.api > run.txt 2>&1 || fail "a plugin with an empty reply failed"
grep -q "produced 0 file(s)" run.txt || fail "an empty reply was not reported"

echo "plugin faults: 7 runs, every refusal covered"
