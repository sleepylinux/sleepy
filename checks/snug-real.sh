#!/usr/bin/env bash
# Run from a Nix-equipped host or CI. Only disposable user profiles are mutated.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
snug_test_pkgs=$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  --expr "(builtins.getFlake \"path:$repo_root\").inputs.nixpkgs.outPath")
SNUG_TEST_BASH=$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  --expr "(import $snug_test_pkgs {}).bash + \"/bin/bash\"")
SNUG_TEST_PATH=$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  --expr "let p = import $snug_test_pkgs {}; in p.lib.makeBinPath [p.coreutils]")
export SNUG_TEST_BASH SNUG_TEST_PATH PYTHONDONTWRITEBYTECODE=1
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from "path:$repo_root" \
  nixpkgs#python3 nixpkgs#bash nixpkgs#coreutils --command python3 "$repo_root/checks/snug-real.py"
