#!/usr/bin/env bash
set -euo pipefail

hyprland_dir=${1:?missing Hyprland configuration directory}
user_config=${2:?missing Hyprland user override path}
install_bin=${3:?missing install executable}
chmod_bin=${4:?missing chmod executable}

if test -L "$hyprland_dir" || { test -e "$hyprland_dir" && ! test -d "$hyprland_dir"; }; then
  echo "Sleepy refuses a non-directory Hyprland configuration path" >&2
  exit 1
fi
if ! test -d "$hyprland_dir"; then
  "$install_bin" -d -m 0700 "$hyprland_dir"
fi

if test -L "$user_config"; then
  echo "Sleepy refuses a symlink at the Hyprland user override path" >&2
  exit 1
elif test -e "$user_config" && ! test -f "$user_config"; then
  echo "Sleepy requires the Hyprland user override path to be a regular file" >&2
  exit 1
elif ! test -e "$user_config"; then
  "$install_bin" -m 0600 /dev/null "$user_config"
else
  # Preserve existing user content while correcting overly broad permissions.
  # The explicit no-dereference flag backs up the symlink rejection above.
  "$chmod_bin" --no-dereference 0600 -- "$user_config"
fi
