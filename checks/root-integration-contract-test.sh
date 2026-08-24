#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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
  if grep -F -- "$pattern" "$repo_root/$file" >/dev/null; then
    printf 'root integration contract: %s unexpectedly contains %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

test -f "$repo_root/modules/home/niri/config/bindings-core.kdl"
test ! -e "$repo_root/modules/home/niri/config/bindings.kdl"
assert_contains modules/home/niri/config/bindings-core.kdl 'Mod+Shift+Escape'
assert_contains modules/home/niri/config/config.kdl 'include "bindings-core.kdl"'
assert_contains modules/home/niri/config/config.kdl 'include optional=true "sleepy-user-bindings.kdl"'
assert_not_contains modules/home/niri/default.nix 'sleepy-user-bindings.kdl'

assert_contains modules/home/session/default.nix 'bindings reconcile'
assert_contains modules/home/session/online-reconcile.sh '--online-required'
assert_contains modules/home/session/online-reconcile.sh 'bindings initialize'
assert_contains modules/home/session/default.nix 'SLEEPY_JQ'
assert_contains modules/home/session/default.nix 'unset NIRI_SOCKET'
assert_contains modules/home/session/default.nix 'test -L "$generated_bindings"'
assert_contains modules/home/session/default.nix 'test -f "$generated_bindings"'
assert_contains modules/home/session/default.nix 'SLEEPY_NIRI_VALIDATOR'
assert_contains modules/home/session/default.nix 'services.gammastep'
assert_contains modules/home/session/default.nix 'entryAfter ["linkGeneration"]'
assert_contains modules/home/session/default.nix 'SLEEPY_SOCKET_ATTEMPTS=150'
assert_contains modules/home/session/online-reconcile.sh 'Niri socket did not become ready before the bounded deadline'
assert_contains modules/home/session/online-reconcile.sh 'test -S'
assert_not_contains modules/home/session/default.nix 'gammastep -m wayland -O'
assert_contains modules/home/quickshell/default.nix 'Requires = ["sleepy-bindings-online.service"]'
assert_contains modules/home/quickshell/default.nix 'After = ["sleepy-bindings-online.service"]'

assert_contains modules/nixos/base/default.nix 'hardware.bluetooth.enable = true'
assert_contains modules/nixos/base/default.nix 'power-profiles-daemon.enable = true'
assert_contains modules/nixos/base/niri-version.nix 'versionAtLeast'
assert_contains modules/nixos/base/niri-version.nix 'config.programs.niri.package.version'
assert_contains checks/default.nix 'sleepy-artwork-assets'
assert_contains checks/default.nix 'sleepy-desktop-qml'
assert_contains checks/default.nix 'sleepy-desktop-package'
assert_contains checks/default.nix 'sleepy-desktop-preview'
assert_contains checks/bindings-contract.nix "'focus-workspace-down;'"
assert_contains checks/bindings-contract.nix "'focus-workspace-up;'"
assert_not_contains checks/bindings-contract.nix "'focus-workspace-next;'"
assert_not_contains checks/bindings-contract.nix "'focus-workspace-previous;'"
assert_contains checks/control-center-contract.nix 'concatStringsSep " " (pkgs.lib.toList gammastepService.Service.ExecStart)'
assert_not_contains checks/update-safety-vm.nix 'rm -f /home/lazy/.config/niri/*.kdl'
assert_contains checks/update-safety-vm.nix 'test -L /home/lazy/.config/niri/config.kdl'
assert_contains checks/update-safety-vm.nix 'SLEEPY_NIRI_VALIDATOR=/bin/false'
assert_contains checks/update-safety-vm.nix 'install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots'
assert_contains checks/update-safety-vm.nix '/home/lazy/.local/state/nix/profiles'
assert_contains checks/update-safety-vm.nix '/home/lazy/.local/share'
assert_contains checks/update-safety-vm.nix 'virtualisation.additionalPaths = [baselineActivationPackage activationPackage]'

printf 'root integration contract self-test: ok\n'
