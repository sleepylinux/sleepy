#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar expressions below are literal source contracts.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() {
  printf 'Hyprland session source contract: %s\n' "$*" >&2
  exit 1
}

require_literal() {
  local file=$1
  local literal=$2
  grep -F -- "$literal" "$repo_root/$file" >/dev/null \
    || fail "$file is missing $literal"
}

reject_literal() {
  local file=$1
  local literal=$2
  if grep -Fi -- "$literal" "$repo_root/$file" >/dev/null; then
    fail "$file unexpectedly contains $literal"
  fi
}

for file in \
  modules/home/hyprland/default.nix \
  modules/home/hyprland/settings.nix \
  modules/home/hyprland/binds.nix \
  modules/home/hyprland/rules.nix \
  modules/home/hyprland/appearance.nix \
  checks/hyprland-config.nix; do
  test -f "$repo_root/$file" || fail "$file does not exist"
done

if test -d "$repo_root/modules/home/niri" \
  && find "$repo_root/modules/home/niri" -type f -print -quit | grep -q .; then
  fail 'the active Home Manager Niri module still exists'
fi
test ! -e "$repo_root/modules/nixos/base/niri-version.nix" \
  || fail 'the active NixOS Niri version assertion still exists'

require_literal modules/home/default.nix './hyprland'
reject_literal modules/home/default.nix './niri'

nixos_session=modules/nixos/session/default.nix
require_literal "$nixos_session" 'programs.hyprland = {'
require_literal "$nixos_session" 'enable = true;'
require_literal "$nixos_session" 'xwayland.enable = true;'
require_literal "$nixos_session" 'withUWSM = true;'
require_literal "$nixos_session" 'programs.uwsm.enable = true;'
require_literal "$nixos_session" 'displayManager.regreet.enable = true;'
require_literal "$nixos_session" 'greetd.enable = true;'
require_literal "$nixos_session" 'default = ["hyprland" "gtk"];'
require_literal "$nixos_session" '"org.freedesktop.impl.portal.FileChooser" = ["gtk"];'
require_literal "$nixos_session" '"org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];'
require_literal "$nixos_session" '"org.freedesktop.impl.portal.Screenshot" = ["hyprland"];'
require_literal "$nixos_session" 'systemd.user.services.gnome-keyring-daemon = {'
keyring_block=$(sed -n \
  '/systemd[.]user[.]services[.]gnome-keyring-daemon = {/,/^  };/p' \
  "$repo_root/$nixos_session")
grep -F 'after = ["graphical-session.target"];' <<<"$keyring_block" >/dev/null \
  || fail 'gnome-keyring-daemon is not ordered after graphical-session.target'
reject_literal "$nixos_session" 'autoLogin'
reject_literal "$nixos_session" 'programs.niri'
reject_literal "$nixos_session" 'xwayland-satellite'

require_literal modules/home/hyprland/default.nix 'wayland.windowManager.hyprland = {'
require_literal modules/home/hyprland/default.nix 'configType = "hyprlang";'
require_literal modules/home/hyprland/default.nix 'systemd.enable = false;'
require_literal modules/home/hyprland/default.nix 'xdg.configFile."uwsm/env".source ='
require_literal modules/home/hyprland/default.nix 'config.home.sessionVariablesPackage'
require_literal modules/home/hyprland/settings.nix 'monitor = [",preferred,auto,1"];'
require_literal modules/home/hyprland/settings.nix 'kb_layout = "us,ru";'
require_literal modules/home/hyprland/settings.nix 'kb_options = "grp:alt_shift_toggle";'
require_literal modules/home/hyprland/binds.nix 'ghostty'
require_literal modules/home/hyprland/binds.nix 'firefox'
require_literal modules/home/hyprland/binds.nix 'shellPackage}/bin/sleepy-shell-ipc'
reject_literal modules/home/hyprland/binds.nix 'pkgs.quickshell'
for method in \
  toggleLauncher \
  toggleDashboard \
  toggleNotifications \
  toggleNexus \
  openPowerMenu \
  lock \
  mediaPlayPause \
  mediaNext \
  mediaPrevious; do
  require_literal modules/home/hyprland/binds.nix "sleepy $method"
done
reject_literal modules/home/hyprland/binds.nix ' drawers '
reject_literal modules/home/hyprland/binds.nix ' mpris '
reject_literal modules/home/hyprland/binds.nix 'requestSessionAction'
reject_literal modules/home/hyprland/binds.nix 'sleepy suspend'
reject_literal modules/home/hyprland/binds.nix 'sleepy logout'
reject_literal modules/home/hyprland/binds.nix 'sleepy reboot'
reject_literal modules/home/hyprland/binds.nix 'sleepy powerOff'
require_literal modules/home/hyprland/rules.nix 'special:scratchpad'
require_literal modules/home/hyprland/appearance.nix 'rounding = 14;'
require_literal modules/home/hyprland/appearance.nix 'blur = {'
require_literal modules/home/hyprland/default.nix 'sleepy-user.conf'
reject_literal modules/home/hyprland/settings.nix 'workspace_swipe'
reject_literal modules/home/hyprland/settings.nix 'pseudotile'
reject_literal modules/home/hyprland/settings.nix 'vfr'
reject_literal modules/home/hyprland/rules.nix 'suppressevent'
reject_literal modules/home/hyprland/rules.nix 'ignorealpha'

session_module=modules/home/session/default.nix
require_literal "$session_module" 'Type = "notify";'
require_literal "$session_module" 'PartOf = ["graphical-session.target"];'
require_literal "$session_module" 'cliphist store'
reject_literal "$session_module" 'sleepy-bindings-online'
reject_literal "$session_module" 'NIRI_SOCKET'
reject_literal "$session_module" 'SLEEPY_NIRI'
reject_literal "$session_module" 'bindings reconcile'
reject_literal "$session_module" 'pkgs.quickshell'

quickshell_module=modules/home/quickshell/default.nix
require_literal "$quickshell_module" 'systemd.user.services.sleepy-shell = {'
require_literal "$quickshell_module" 'ExecStart = "${config.sleepy.shellPackage}/bin/sleepy-shell";'
require_literal "$quickshell_module" 'Wants = ["sleepy-session.service"];'
require_literal "$quickshell_module" 'After = ["sleepy-session.service"];'
reject_literal "$quickshell_module" 'programs.quickshell'
reject_literal "$quickshell_module" 'systemd.user.services.quickshell'
reject_literal "$quickshell_module" 'pkgs.quickshell'
reject_literal "$quickshell_module" 'Requires = ["sleepy-session.service"'
reject_literal "$quickshell_module" 'sleepy-bindings-online'
reject_literal "$nixos_session" '    quickshell'

locker_module=modules/home/locker/default.nix
require_literal "$locker_module" 'PartOf = ["graphical-session.target"];'
require_literal "$locker_module" 'Install.WantedBy = ["graphical-session.target"];'

require_literal checks/default.nix 'hyprlandConfig = pkgs.callPackage ./hyprland-config.nix'
require_literal checks/default.nix 'hyprland-config = hyprlandConfig;'
require_literal checks/hyprland-config.nix 'export XDG_RUNTIME_DIR="$runtime_dir"'
reject_literal checks/default.nix 'niriConfig ='
reject_literal checks/default.nix 'niriVersionContract ='
reject_literal checks/default.nix 'niri-config ='
reject_literal checks/default.nix 'niri-version-contract ='

if rg -n -i --glob '*.nix' \
  'programs[.]niri|pkgs[.]niri|xwayland-satellite|modules/home/niri|niri-version' \
  "$repo_root/modules" "$repo_root/profiles"; then
  fail 'the active module graph still contains Niri wiring'
fi

printf 'Hyprland session source contract: ok\n'
