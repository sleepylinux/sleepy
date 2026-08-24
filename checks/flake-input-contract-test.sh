#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/flake-input-contract.sh"
manifest="$repo_root/components/desktop-m1.json"
fixture=$(mktemp -d /tmp/sleepy-flake-input-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

cat >"$fixture/valid.nix" <<'EOF'
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sleepy-sdk = {
      url = "github:sleepylinux/sleepy-sdk/4c4f7989b957f41f3748ddfb092b0348e2ba9e88";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-session = {
      url = "github:sleepylinux/sleepy-session/76937a484ffa444572c9ae1460029e573fb108ca";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-artwork = {
      url = "github:sleepylinux/sleepy-artwork/7785ac5dac0daa6ac1a619f1e2a9a1b1d1374da1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-desktop = {
      url = "github:sleepylinux/sleepy-desktop/b69fd4d97895600e029e10621a61113ad795dbd8";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {};
}
EOF

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

bash "$contract" "$fixture/valid.nix" "$manifest"

if bash "$contract" "$fixture/computed.nix" "$manifest" >/dev/null 2>&1; then
  printf 'flake input contract accepted a computed inputs thunk\n' >&2
  exit 1
fi

sed \
  's/76937a484ffa444572c9ae1460029e573fb108ca/0000000000000000000000000000000000000000/' \
  "$fixture/valid.nix" >"$fixture/drifted.nix"
if bash "$contract" "$fixture/drifted.nix" "$manifest" >/dev/null 2>&1; then
  printf 'flake input contract accepted revision drift from the manifest\n' >&2
  exit 1
fi

bash "$contract" "$repo_root/flake.nix" "$manifest"
printf 'flake input contract self-test: ok\n'
