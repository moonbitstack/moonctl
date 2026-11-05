#!/usr/bin/env bash
# Generated code is `moon fmt`-clean.
#
#   scripts/check_scaffold_fmt.sh [path-to-mctl]
#
# Scaffolds one project of every kind, records them in a throwaway git repository,
# runs `moon fmt` in each, and fails if the formatter changed anything: what mctl
# writes is what `moon fmt` would write, so a reviewer never has to reformat a
# freshly generated project before touching it.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mctl="${1:-$here/_build/native/debug/build/cmd/mctl/mctl.exe}"
if [[ ! -x "$mctl" ]]; then
  echo "no mctl at $mctl; build it first (moon build --target native)" >&2
  exit 2
fi
mctl="$(cd "$(dirname "$mctl")" && pwd)/$(basename "$mctl")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q .
# compare bytes, not line endings: git's autocrlf would report every file as
# changed on Windows and hide what the formatter actually did
git config core.autocrlf false
git config core.safecrlf false
printf '* -text\n' >.gitattributes
printf '_build/\n.mooncakes/\n' >.gitignore

for kind in api rpc gql mcp model; do
  "$mctl" "$kind" new "demo$kind" >/dev/null
done

git add -A
git -c user.name=ci -c user.email=ci@example.com commit -qm generated

status=0
for kind in api rpc gql mcp model; do
  if ! (cd "demo$kind" && moon fmt >/dev/null); then
    echo "moon fmt failed in demo$kind" >&2
    status=1
  fi
done
((status == 0)) || exit "$status"

if ! git diff --quiet; then
  echo "generated code is not moon fmt-clean:" >&2
  git --no-pager diff --stat >&2
  git --no-pager diff >&2 | head -120
  exit 1
fi

echo "generated code is moon fmt-clean (api, rpc, gql, mcp, model)"
