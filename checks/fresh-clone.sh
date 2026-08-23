#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)
clone_root=$(mktemp -d "${TMPDIR:-/tmp}/sleepy-fresh-clone.XXXXXX")
trap 'rm -rf -- "$clone_root"' EXIT

git clone --quiet --no-local -- "$repo_root" "$clone_root/repo"
cd "$clone_root/repo"

test ! -e local
test ! -L local
test ! -e secrets
test ! -L secrets

cp -- flake.lock "$clone_root/flake.lock"
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel \
  --no-link \
  --no-write-lock-file
cmp --silent -- flake.lock "$clone_root/flake.lock"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
