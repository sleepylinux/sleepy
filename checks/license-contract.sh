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
manifest=$(mktemp /tmp/sleepy-license-sources.XXXXXX)
trap 'rm -f -- "$manifest"' EXIT

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

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_root" ls-files -z >"$manifest"
else
  find "$repo_root" \
    -path "$repo_root/.git" -prune -o \
    -type f -printf '%P\0' >"$manifest"
fi

or_later='GPL-3.0-'
or_later+='or-later'
mit_nix='licenses.'
mit_nix+='mit'
mit_spdx='SPDX-License-Identifier: '
mit_spdx+='MIT'
mit_title='MIT'
mit_title+=' License'
mit_toml='license = "'
mit_toml+='MIT"'
mit_json='"license": "'
mit_json+='MIT"'

failed=0
while IFS= read -r -d '' relative_path; do
  source_path="$repo_root/$relative_path"
  if test ! -f "$source_path"; then
    continue
  fi

  if rg -I -n -F \
    -e "$or_later" \
    -e "$mit_nix" \
    -e "$mit_spdx" \
    -e "$mit_title" \
    -e "$mit_toml" \
    -e "$mit_json" \
    "$source_path"; then
    printf 'license contract: forbidden license metadata or intent: %s\n' \
      "$relative_path" >&2
    failed=1
  fi
done <"$manifest"

if test "$failed" -ne 0; then
  exit 1
fi

if test ! -f "$repo_root/README.md" || \
  ! rg -F -q -- 'GPL-3.0-only' "$repo_root/README.md"; then
  printf 'license contract: README must declare GPL-3.0-only\n' >&2
  exit 1
fi

printf 'license contract: ok\n'
