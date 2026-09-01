#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar expressions below are literal source contracts.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

require_literal() {
  local file=$1
  local literal=$2
  if ! grep -F -- "$literal" "$repo_root/$file" >/dev/null; then
    printf 'desktop M3 root contract: %s is missing %s\n' "$file" "$literal" >&2
    exit 1
  fi
}

reject_literal() {
  local file=$1
  local literal=$2
  if grep -F -- "$literal" "$repo_root/$file" >/dev/null; then
    printf 'desktop M3 root contract: %s unexpectedly contains %s\n' "$file" "$literal" >&2
    exit 1
  fi
}

session_module=modules/home/session/default.nix
quickshell_module=modules/home/quickshell/default.nix
update_vm=checks/update-safety-vm.nix
ci_workflow=.github/workflows/check.yml

require_literal "$session_module" 'sleepy-sessiond'
require_literal "$session_module" 'Type = "notify";'
require_literal "$session_module" 'NotifyAccess = "main";'
require_literal "$session_module" 'Restart = "on-failure";'
require_literal "$session_module" 'RuntimeDirectory = "sleepy";'
require_literal "$session_module" 'RuntimeDirectoryMode = "0700";'
require_literal "$session_module" 'PATH=${sessionRuntimePath}'
reject_literal "$session_module" 'ExecStart = "/'

require_literal "$quickshell_module" 'Wants = ["sleepy-session.service"'
require_literal "$quickshell_module" 'After = ["sleepy-session.service"'
require_literal "$quickshell_module" 'systemd.user.services.sleepy-shell = {'
reject_literal "$quickshell_module" 'Requires = ["sleepy-session.service"'
reject_literal "$quickshell_module" 'systemd.user.services.quickshell'

for durable_path in \
  '.config/sleepy/settings.json' \
  '.config/sleepy/themes' \
  '.config/sleepy/overrides.json' \
  '.local/state/sleepy/presets.json' \
  '.local/state/sleepy/launcher.json' \
  '.local/state/sleepy/notifications/active.json' \
  '.local/state/sleepy/notifications/archive.json'; do
  require_literal "$update_vm" "$durable_path"
done

require_literal "$update_vm" '["session", "control", "notification", "osd", "daily", "theme", "desktop", "desktop-control", "secret"]'
require_literal "$update_vm" '/run/user/$uid/sleepy/{socket_name}.sock'
require_literal "$update_vm" 'stat -c %a /run/user/$uid/sleepy/{socket_name}.sock) = 600'
require_literal "$update_vm" 'systemctl --user is-active sleepy-session.service'
require_literal "$update_vm" 'systemctl --user stop sleepy-session.service'
require_literal "$update_vm" 'test ! -e /run/user/$uid/sleepy'

require_literal checks/default.nix 'pristine-login-vm'
require_literal flake.nix 'sleepy-m2-baseline = {'
require_literal flake.nix 'github:sleepylinux/sleepy/563ae07b50ccc8c5332e1fb0352d351d46c7f615'
require_literal flake.nix 'baselineActivationPackage = inputs.sleepy-m2-baseline.homeConfigurations'
require_literal flake.nix 'baselineSessionPackage = inputs.sleepy-m2-baseline.packages.${system}.sleepy-session;'
require_literal "$update_vm" '${baselineSessionPackage}/bin/sleepyctl presets duplicate'
require_literal "$update_vm" 'VM preserved theme'
require_literal "$update_vm" 'Message 11'
require_literal "$update_vm" 'assert_state_unchanged("M3 daemon startup", preserved_before, preserved_state_manifest)'
require_literal "$update_vm" 'systemctl --user stop sleepy-test-session.target graphical-session.target'
require_literal "$update_vm" 'systemctl stop user@$uid.service'
require_literal "$update_vm" 'loginctl disable-linger lazy'
reject_literal flake.nix 'sleepy-m1-baseline'
require_literal "$ci_workflow" 'bash checks/component-lock.sh components/desktop-m1.json components/desktop-m2-baseline.json flake.lock'
reject_literal "$ci_workflow" 'bash checks/component-lock.sh components/desktop-m1.json components/desktop-m1-baseline.json flake.lock'
require_literal "$ci_workflow" 'nix develop --command bash checks/desktop-m3-root-contract-test.sh'
test -f "$repo_root/docs/roadmaps/desktop-m4-installer-hardware-validation.md"

printf 'desktop M3 root contract self-test: ok\n'
