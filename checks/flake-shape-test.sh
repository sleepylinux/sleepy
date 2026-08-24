#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/flake-shape.sh"
fixture=$(mktemp -d /tmp/sleepy-flake-shape.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

cat >"$fixture/valid.nix" <<'EOF'
# A line comment may precede a flake.
/* A block comment may too. */
{
  description = "fixture";
}
EOF

cat >"$fixture/invalid.nix" <<'EOF'
let
  value = "not a literal top-level attribute set";
in {
  description = value;
}
EOF

bash "$contract" "$fixture/valid.nix"
if bash "$contract" "$fixture/invalid.nix" >/dev/null 2>&1; then
  printf 'flake shape contract accepted a top-level let expression\n' >&2
  exit 1
fi

bash "$contract" "$repo_root/flake.nix"
printf 'flake shape self-test: ok\n'
