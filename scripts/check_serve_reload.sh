#!/usr/bin/env bash
# `mctl serve --reload` end to end, on a real project and real processes: a save restarts the
# program, a save that does not compile waits for the next one, and stopping mctl stops the program.
#
#     moon build src/cmd/mctl --target native
#     bash scripts/check_serve_reload.sh
set -u

mctl="$PWD/_build/native/debug/build/cmd/mctl/mctl.exe"
work="$(mktemp -d)"
cd "$work"

cat > moon.mod <<'EOF'
name = "probe/reload"

version = "0.0.1"

import {
  "moonbitlang/async@0.22.5",
}
EOF

cat > moon.pkg <<'EOF'
import {
  "moonbitlang/async",
  "moonbitlang/async/fs",
}

pkgtype(kind: "executable")

supported_targets = "+native"
EOF

program() {
  cat > main.mbt <<EOF
async fn main {
  @fs.write_file("alive", b"$1", create_mode=CreateOrTruncate)
  @async.sleep(600000)
}
EOF
}

wait_for() {
  for _ in $(seq 1 240); do
    [ "$(cat alive 2>/dev/null)" = "$1" ] && return 0
    sleep 0.5
  done
  echo "FAIL: the program never wrote $1; it wrote $(cat alive 2>/dev/null)"
  cat mctl.log
  exit 1
}

program one
"$mctl" serve --reload --reload-delay 0.1 > mctl.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null' EXIT

wait_for one
echo "ok   the first build runs"

program two
wait_for two
echo "ok   a save restarts it"

echo 'async fn main { this does not compile' > main.mbt
for _ in $(seq 1 240); do
  grep -q "^Error" mctl.log && break
  sleep 0.5
done
grep -q "^Error" mctl.log || { echo "FAIL: the broken save went unnoticed"; cat mctl.log; exit 1; }
echo "ok   a save that does not compile is reported"

program three
wait_for three
echo "ok   the next save recovers"

binary=$(find _build -type f -name 'reload*' -perm -u+x | head -1)
kill "$pid"
wait "$pid" 2>/dev/null
trap - EXIT
sleep 1
if pgrep -f "$binary" > /dev/null; then
  echo "FAIL: stopping mctl left the program running"
  pkill -f "$binary"
  exit 1
fi
echo "ok   stopping mctl stops the program"
rm -rf "$work"
