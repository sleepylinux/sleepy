#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/flake-input-contract.sh"
manifest="$repo_root/components/desktop-m1.json"
baseline_manifest="$repo_root/components/desktop-m1-baseline.json"
fixture=$(mktemp -d /tmp/sleepy-flake-input-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

cp "$repo_root/flake.nix" "$fixture/valid.nix"

cat >"$fixture/computed.nix" <<'EOF'
{
  inputs = let
    manifest = builtins.fromJSON (builtins.readFile ./components.json);
  in {
    sleepy-sdk.url = manifest.inputs.sleepy-sdk.url;
  };

  outputs = inputs: {};
}
EOF

bash "$contract" "$fixture/valid.nix" "$manifest" "$baseline_manifest"

if bash "$contract" "$fixture/computed.nix" "$manifest" "$baseline_manifest" >/dev/null 2>&1; then
  printf 'flake input contract accepted a computed inputs thunk\n' >&2
  exit 1
fi

session_revision=$(jq -er '.inputs["sleepy-session"].revision' "$manifest")
sed \
  "s/$session_revision/0000000000000000000000000000000000000000/" \
  "$fixture/valid.nix" >"$fixture/drifted.nix"
if bash "$contract" "$fixture/drifted.nix" "$manifest" "$baseline_manifest" >/dev/null 2>&1; then
  printf 'flake input contract accepted revision drift from the manifest\n' >&2
  exit 1
fi

bash "$contract" "$repo_root/flake.nix" "$manifest" "$baseline_manifest"
printf 'flake input contract self-test: ok\n'
