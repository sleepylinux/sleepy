#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/license-contract.sh"
fixture=$(mktemp -d /tmp/sleepy-license-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

mkdir -p "$fixture/docs" "$fixture/packages/fallback"
cp "$repo_root/LICENSE" "$fixture/LICENSE"
printf '%s\n' 'Sleepy Linux is licensed under GPL-3.0-only.' \
  >"$fixture/README.md"
printf '%s\n' '{lib, ...}: {meta.license = lib.licenses.gpl3Only;}' \
  >"$fixture/packages/fallback/default.nix"

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

or_later='GPL-3.0-'
or_later+='or-later'
mit_nix='lib.licenses.'
mit_nix+='mit'
mit_spdx='SPDX-License-Identifier: '
mit_spdx+='MIT'

assert_rejected or-later-intent docs/probe.md "$or_later"
assert_rejected nix-mit-metadata packages/fallback/probe.nix "$mit_nix"
assert_rejected spdx-mit-metadata docs/probe.md "$mit_spdx"

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
