#!/usr/bin/env bash
set -euo pipefail

for required_command in find git rg sha256sum wc; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'license contract: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=${1:-$(git rev-parse --show-toplevel)}
repo_root=$(cd "$repo_root" && pwd -P)
license="$repo_root/LICENSE"

expected_hash=fb981668c18a279e285fc4d83fba1e836cc84dd4daa73c9697d3cfd2d8aca6e0
expected_size=34674

test -f "$license"
actual_hash=$(sha256sum "$license" | cut -d' ' -f1)
actual_size=$(wc -c <"$license")

if test "$actual_hash" != "$expected_hash" || \
  test "$actual_size" -ne "$expected_size"; then
  printf 'license contract: canonical LICENSE mismatch: hash=%s size=%s\n' \
    "$actual_hash" "$actual_size" >&2
  exit 1
fi

if test ! -f "$repo_root/README.md" || \
  ! rg -F -q -- 'GPL-3.0-only' "$repo_root/README.md"; then
  printf 'license contract: README must declare GPL-3.0-only\n' >&2
  exit 1
fi

if test -d "$repo_root/packages"; then
  while IFS= read -r -d '' package_dir; do
    package_file="$package_dir/default.nix"
    if test ! -f "$package_file" || \
      ! rg -q -- \
        'meta\.license[[:space:]]*=[[:space:]]*lib\.licenses\.gpl3Only[[:space:]]*;' \
        "$package_file"; then
      printf 'license contract: Sleepy package must declare GPL-3.0-only: %s\n' \
        "${package_dir#"$repo_root/"}" >&2
      exit 1
    fi
  done < <(
    find "$repo_root/packages" -mindepth 1 -maxdepth 1 \
      -type d -name 'sleepy-*' -print0
  )
fi

printf 'license contract: ok\n'
