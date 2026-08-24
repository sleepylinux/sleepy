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
      url = "github:sleepylinux/sleepy-sdk/2edbe8310eee69c40e4f75924da67a57942bd1c3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-session = {
      url = "github:sleepylinux/sleepy-session/1e8863839b5c4310bce251b7e10ed15926039930";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-artwork = {
      url = "github:sleepylinux/sleepy-artwork/0dd59cc9d8a77700f7a415997e3dcde396f55e99";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-desktop = {
      url = "github:sleepylinux/sleepy-desktop/a88fba369d3926981c46b837c88483553559a60a";
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
  's/1e8863839b5c4310bce251b7e10ed15926039930/0000000000000000000000000000000000000000/' \
  "$fixture/valid.nix" >"$fixture/drifted.nix"
if bash "$contract" "$fixture/drifted.nix" "$manifest" >/dev/null 2>&1; then
  printf 'flake input contract accepted revision drift from the manifest\n' >&2
  exit 1
fi

bash "$contract" "$repo_root/flake.nix" "$manifest"
printf 'flake input contract self-test: ok\n'
