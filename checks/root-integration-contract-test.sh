#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar expressions below are literal source contracts.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

assert_contains() {
  local file=$1
  local pattern=$2
  if ! grep -F -- "$pattern" "$repo_root/$file" >/dev/null; then
    printf 'root integration contract: %s is missing %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file=$1
  local pattern=$2
  if grep -Fi -- "$pattern" "$repo_root/$file" >/dev/null; then
    printf 'root integration contract: %s unexpectedly contains %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

bash "$repo_root/checks/hyprland-session-contract-test.sh"

assert_contains modules/home/session/default.nix 'Type = "notify";'
assert_contains modules/home/session/default.nix 'NotifyAccess = "main";'
assert_contains modules/home/session/default.nix 'systemd.user.services = {'
assert_contains modules/home/session/default.nix 'sleepy-clipboard = {'
assert_contains modules/home/session/default.nix 'gammastep = {'
assert_not_contains modules/home/session/default.nix 'gammastep -m wayland -O'
assert_not_contains modules/home/session/default.nix 'sleepy-bindings-online'
assert_not_contains modules/home/session/default.nix 'NIRI_SOCKET'

assert_contains modules/home/quickshell/default.nix 'Wants = ["sleepy-session.service"]'
assert_contains modules/home/quickshell/default.nix 'After = ["sleepy-session.service"]'
assert_contains modules/home/quickshell/default.nix 'systemd.user.services.sleepy-shell = {'
assert_not_contains modules/home/quickshell/default.nix 'Requires = ["sleepy-session.service"'
assert_not_contains modules/home/quickshell/default.nix 'systemd.user.services.quickshell'

assert_contains modules/home/hyprland/default.nix 'systemd.enable = false;'
assert_contains modules/home/hyprland/default.nix 'sleepy-user.conf'
assert_contains modules/home/hyprland/binds.nix 'sleepy lock'
assert_contains modules/home/hyprland/settings.nix 'gesture = ["3, horizontal, workspace"]'
assert_contains modules/home/hyprland/rules.nix 'match:class'
assert_contains modules/home/hyprland/rules.nix 'match:namespace'

assert_contains modules/nixos/base/default.nix 'hardware.bluetooth.enable = true'
assert_contains modules/nixos/base/default.nix 'power-profiles-daemon.enable = true'
assert_not_contains modules/nixos/base/default.nix 'niri-version'
assert_contains modules/nixos/session/default.nix 'programs.hyprland = {'
assert_contains modules/nixos/session/default.nix 'programs.uwsm.enable = true;'

assert_contains checks/default.nix 'hyprland-config = hyprlandConfig;'
assert_contains checks/default.nix 'sleepy-artwork-assets'
assert_contains checks/default.nix 'sleepy-desktop-qml'
assert_contains checks/default.nix 'sleepy-desktop-package'
assert_contains checks/default.nix 'sleepy-desktop-preview'
assert_not_contains checks/default.nix 'niri-config ='
assert_not_contains checks/default.nix 'niri-version-contract ='

assert_contains .github/workflows/check.yml 'timeout-minutes:'
assert_contains .github/workflows/check.yml 'nix flake check --all-systems --no-build --show-trace'
assert_contains .github/workflows/check.yml 'nix build .#checks.x86_64-linux.hyprland-config --no-link -L'
assert_contains .github/workflows/check.yml 'nix build .#checks.x86_64-linux.session-contract --no-link -L'
assert_contains .github/workflows/check.yml 'test -c /dev/kvm'
assert_contains .github/workflows/check.yml 'system-features = nixos-test benchmark big-parallel kvm'

# Prior-generation validation remains the only active place where Niri paths
# are expected. It must preserve legacy bytes and never delete them.
assert_not_contains checks/update-safety-vm.nix 'rm -f /home/lazy/.config/niri/*.kdl'
assert_contains checks/update-safety-vm.nix '/home/lazy/.config/niri/sleepy-user-bindings.kdl'
assert_contains checks/update-safety-vm.nix 'test ! -e /home/lazy/.config/niri/{static_name}.kdl'
assert_contains checks/update-safety-vm.nix 'machine.fail("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")'
assert_contains checks/update-safety-vm.nix 'test $(cat /home/lazy/protected-override) = protected'
assert_contains checks/update-safety-vm.nix 'install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots'
assert_contains checks/update-safety-vm.nix '/home/lazy/.local/state/nix/profiles'
assert_contains checks/update-safety-vm.nix '/home/lazy/.local/share'
assert_contains checks/update-safety-vm.nix 'virtualisation.additionalPaths = [baselineActivationPackage baselineSessionPackage activationPackage]'

printf 'root integration contract self-test: ok\n'
