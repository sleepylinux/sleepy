#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/license-contract.sh"
fixture=$(mktemp -d /tmp/sleepy-license-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

mkdir -p \
  "$fixture/docs" \
  "$fixture/packages/sleepy-fallback" \
  "$fixture/third_party/example"
cp "$repo_root/LICENSE" "$fixture/LICENSE"
printf '%s\n' 'Sleepy Linux is licensed under GPL-3.0-only.' \
  >"$fixture/README.md"
printf '%s\n' '{lib, ...}: {meta.license = lib.licenses.gpl3Only;}' \
  >"$fixture/packages/sleepy-fallback/default.nix"

bash "$contract" "$fixture"

assert_rejected() {
  local name=$1
  local relative_path=$2
  local payload=$3
  local probe="$fixture/$relative_path"

  printf '%s\n' "$payload" >"$probe"
  if bash "$contract" "$fixture" >/dev/null 2>&1; then
    rm -f -- "$probe"
    printf 'license contract accepted forbidden fixture: %s\n' "$name" >&2
    return 1
  fi
  rm -f -- "$probe"
}

assert_accepted() {
  local name=$1
  local relative_path=$2
  local payload=$3
  local probe="$fixture/$relative_path"

  mkdir -p "$(dirname "$probe")"
  printf '%s\n' "$payload" >"$probe"
  if ! bash "$contract" "$fixture" >/dev/null 2>&1; then
    rm -f -- "$probe"
    printf 'license contract rejected unrelated license fixture: %s\n' \
      "$name" >&2
    return 1
  fi
  rm -f -- "$probe"
}

assert_accepted third-party-cargo-mit third_party/example/Cargo.toml \
  'license = "MIT"'
assert_accepted third-party-nix-apache third_party/example/default.nix \
  '{lib, ...}: {meta.license = lib.licenses.asl20;}'
assert_accepted third-party-spdx-bsd third_party/example/source.c \
  '// SPDX-License-Identifier: BSD-3-Clause'
assert_accepted docs-may-discuss-other-licenses docs/probe.md \
  'MIT, Apache-2.0, BSD-3-Clause, GPL-2.0-only and GPL-3.0-or-later.'

mkdir -p "$fixture/packages/sleepy-wrong" "$fixture/packages/sleepy-missing"
assert_rejected sleepy-package-wrong-license \
  packages/sleepy-wrong/default.nix \
  '{lib, ...}: {meta.license = lib.licenses.mit;}'
assert_rejected sleepy-package-missing-license \
  packages/sleepy-missing/default.nix \
  '{...}: {pname = "sleepy-missing";}'

cp "$fixture/LICENSE" "$fixture/LICENSE.good"
chmod u+w "$fixture/LICENSE"
printf '\n' >>"$fixture/LICENSE"
if bash "$contract" "$fixture" >/dev/null 2>&1; then
  printf 'license contract accepted modified canonical license bytes\n' >&2
  exit 1
fi
mv "$fixture/LICENSE.good" "$fixture/LICENSE"

bash "$contract" "$repo_root"
printf 'license contract self-test: ok\n'
