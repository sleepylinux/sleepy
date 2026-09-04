#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
helper="$repo_root/modules/home/hyprland/ensure-user-config.sh"

fail() {
  printf 'Hyprland user config contract: %s\n' "$*" >&2
  exit 1
}

test -f "$helper" || fail 'production helper is missing'
grep -F './ensure-user-config.sh' "$repo_root/modules/home/hyprland/default.nix" >/dev/null \
  || fail 'Home Manager activation does not invoke the production helper'

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

hyprland_dir="$fixture/config/hypr"
user_config="$hyprland_dir/sleepy-user.conf"
install -d -m 0700 "$hyprland_dir"
printf '%s\n' '# preserve this user override byte-for-byte' >"$user_config"
chmod 0644 "$user_config"
before=$(sha256sum "$user_config")

bash "$helper" "$hyprland_dir" "$user_config" "$(command -v install)" "$(command -v chmod)"

test "$(stat -c %a "$user_config")" = 600 \
  || fail 'existing regular override was not corrected to mode 0600'
test "$(sha256sum "$user_config")" = "$before" \
  || fail 'mode correction changed existing override contents'

protected="$fixture/protected"
printf '%s\n' protected >"$protected"
chmod 0644 "$protected"
protected_before=$(sha256sum "$protected")
protected_mode=$(stat -c %a "$protected")
rm "$user_config"
ln -s "$protected" "$user_config"

if bash "$helper" "$hyprland_dir" "$user_config" "$(command -v install)" "$(command -v chmod)"; then
  fail 'helper accepted a symlink at the user override path'
fi
test "$(sha256sum "$protected")" = "$protected_before" \
  || fail 'symlink rejection changed the protected target contents'
test "$(stat -c %a "$protected")" = "$protected_mode" \
  || fail 'symlink rejection changed the protected target mode'

printf 'Hyprland user config contract: ok\n'
