#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  printf 'update safety contract: required command not found: rg\n' >&2
  exit 127
fi

if test "$#" -lt 3; then
  printf 'usage: %s <home-files> <activation-script> <home-manager-source>...\n' \
    "${0##*/}" >&2
  exit 2
fi

home_files=$1
activation_script=$2
shift 2

if ! test -f "$activation_script"; then
  printf 'update safety contract: activation script is missing: %s\n' \
    "$activation_script" >&2
  exit 1
fi

for relative_path in \
  '.config/sleepy/settings.json' \
  '.config/sleepy/themes' \
  '.config/sleepy/overrides.json' \
  '.local/state/sleepy/presets.json' \
  '.local/state/sleepy/launcher.json' \
  '.local/state/sleepy/notifications' \
  '.config/niri/sleepy-user-bindings.kdl'; do
  managed_path="$home_files/$relative_path"
  if test -e "$managed_path" || test -L "$managed_path"; then
    printf 'Home Manager must not manage the user-owned XDG default path: %s\n' \
      "$relative_path" >&2
    exit 1
  fi
done

mutable_pattern='settings\.json|presets\.json|overrides\.json|launcher\.json|sleepy/themes|sleepy/notifications'

if rg -n "$mutable_pattern" "$activation_script"; then
  printf 'Home Manager activation must not reference mutable Sleepy state\n' >&2
  exit 1
fi

if rg -n --glob '*.nix' \
  "$mutable_pattern|force[[:space:]]*=[[:space:]]*true[[:space:]]*;" \
  "$@"; then
  printf 'Home Manager sources must not reference mutable Sleepy state or force file ownership\n' >&2
  exit 1
fi

printf 'update safety contract: ok\n'
