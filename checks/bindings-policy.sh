#!/usr/bin/env bash
set -euo pipefail

for required_command in awk grep mktemp sort uniq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'bindings policy: missing command: %s\n' "$required_command" >&2
    exit 127
  }
done

if test "$#" -ne 2; then
  printf 'usage: %s <bindings-core.kdl> <generated.kdl>\n' "${0##*/}" >&2
  exit 2
fi

core=$1
generated=$2
fixture=$(mktemp -d /tmp/sleepy-bindings-policy-check.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

awk '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*\/\// { next }
  /^[[:space:]]*binds[[:space:]]*\{[[:space:]]*$/ { next }
  /^[[:space:]]*\}[[:space:]]*$/ { next }
  { print }
' \
  "$core" >"$fixture/core-bindings"
if test "$(wc -l <"$fixture/core-bindings")" -ne 1 ||
  ! grep -Eq '^[[:space:]]*Mod\+Shift\+Escape[[:space:]]*\{[[:space:]]*spawn[[:space:]]+"ghostty";[[:space:]]*\}[[:space:]]*$' \
    "$fixture/core-bindings"; then
  printf 'bindings policy: core must contain exactly the recovery shell chord\n' >&2
  exit 1
fi

awk '
  /^[[:space:]]*\/\// { next }
  /^[[:space:]]*binds[[:space:]]*\{/ { next }
  /^[[:space:]]*\}[[:space:]]*$/ { next }
  index($0, "{") { print $1 }
' \
  "$core" "$generated" | sort >"$fixture/chords"
if uniq -d "$fixture/chords" | grep . >/dev/null; then
  printf 'bindings policy: duplicate effective chord across core/generated includes\n' >&2
  exit 1
fi

if grep -E \
  'spawn[[:space:]]+"(systemctl|reboot|poweroff|shutdown|niri)"([^;]*"(reboot|poweroff|power-off|quit)")?|\{[[:space:]]*quit;' \
  "$generated" >/dev/null; then
  printf 'bindings policy: generated bindings contain a direct destructive action\n' >&2
  exit 1
fi

printf 'bindings policy: ok\n'
