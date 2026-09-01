#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar expressions below are literal source contracts.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'locker lifecycle contract: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local pattern=$2
  grep -F -- "$pattern" "$repo_root/$file" >/dev/null \
    || fail "$file is missing $pattern"
}

assert_not_contains() {
  local file=$1
  local pattern=$2
  if grep -Fi -- "$pattern" "$repo_root/$file" >/dev/null; then
    fail "$file unexpectedly contains $pattern"
  fi
}

pam_module=modules/nixos/session/pam.nix
locker_module=modules/home/locker/default.nix

test -f "$repo_root/$pam_module" || fail "$pam_module does not exist"
test -f "$repo_root/$locker_module" || fail "$locker_module does not exist"
test -f "$repo_root/checks/locker-lifecycle.nix" \
  || fail 'checks/locker-lifecycle.nix does not exist'

assert_contains checks/default.nix 'lockerLifecycle = import ./locker-lifecycle.nix'
assert_contains checks/default.nix 'checks/locker-lifecycle-test.sh'
assert_contains checks/default.nix 'locker-lifecycle = lockerLifecycle;'
assert_contains checks/locker-lifecycle.nix \
  'pkgs.lib.toList locker.Service.ExecStart == ["${homeConfig.sleepy.lockerPackage}/bin/sleepy-locker"]'
assert_contains checks/locker-lifecycle.nix \
  'pkgs.lib.toList failsafe.Service.ExecStart == ["${pkgs.uwsm}/bin/uwsm stop"]'

assert_contains modules/nixos/session/default.nix './pam.nix'
assert_contains "$pam_module" 'security.pam.services.sleepy-locker = {}'

assert_contains modules/home/default.nix './locker'
assert_contains modules/home/options.nix 'lockerPackage = lib.mkOption'
assert_contains profiles/desktop.nix 'lockerPackage = pkgs.sleepy-locker;'
assert_contains overlays/default.nix 'sleepy-locker'

assert_contains "$locker_module" 'sleepy-locker = {'
assert_contains "$locker_module" 'PartOf = ["graphical-session.target"]'
assert_contains "$locker_module" 'After = ["graphical-session.target"]'
assert_contains "$locker_module" 'Requisite = ["graphical-session.target"]'
assert_contains "$locker_module" 'OnFailure = ["sleepy-locker-failsafe.service"]'
assert_contains "$locker_module" 'ExecStart = "${config.sleepy.lockerPackage}/bin/sleepy-locker"'
assert_contains "$locker_module" 'Restart = "no"'
assert_contains "$locker_module" 'KillMode = "control-group"'
assert_not_contains "$locker_module" 'ExecStop'
assert_not_contains "$locker_module" 'sleepy-locker-control'
assert_not_contains "$locker_module" 'Restart = "always"'
assert_not_contains "$locker_module" 'RestartSec'
assert_not_contains "$locker_module" 'StartLimitIntervalSec'
assert_not_contains "$locker_module" 'StartLimitBurst'
assert_contains "$locker_module" 'Install.WantedBy = ["graphical-session.target"]'

assert_contains "$locker_module" 'sleepy-locker-failsafe = {'
assert_contains "$locker_module" 'ExecStart = "${pkgs.uwsm}/bin/uwsm stop"'
assert_contains "$locker_module" 'Type = "oneshot"'
assert_contains "$locker_module" 'TimeoutStartSec = 15'
assert_not_contains "$locker_module" '/bin/sh'
assert_not_contains "$locker_module" '/bin/bash'
assert_not_contains "$locker_module" 'unlock'

assert_contains modules/home/session/default.nix 'Wants = lib.optionals (config.sleepy.lockerPackage != null) ["sleepy-locker.service"]'
assert_contains modules/home/session/default.nix '++ lib.optionals (config.sleepy.lockerPackage != null) ["sleepy-locker.service"]'
assert_contains modules/home/session/default.nix '"SLEEPY_LOCKER_SOCKET=%t/sleepy/locker.sock"'
assert_not_contains modules/home/session/default.nix 'Requires = ["sleepy-locker.service"]'

printf 'locker lifecycle source contract: ok\n'
