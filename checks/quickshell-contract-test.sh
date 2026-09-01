#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  printf 'quickshell contract self-test: required command not found: rg\n' >&2
  exit 127
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/quickshell-contract.sh"
fixture=$(mktemp -d /tmp/sleepy-quickshell-contract.XXXXXX)
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/modules" \
  "$fixture/packages/sleepy-shell/src/modules/panel" \
  "$fixture/packages/sleepy-shell/src/services" \
  "$fixture/packages/sleepy-shell/src/widgets"
: >"$fixture/packages/sleepy-shell/src/modules/panel/Panel.qml"
: >"$fixture/packages/sleepy-shell/src/services/NiriService.qml"

bash "$contract" "$fixture"

rm -f "$fixture/packages/sleepy-shell/src/services/NiriService.qml"
if bash "$contract" "$fixture" >/dev/null 2>&1; then
  printf 'contract accepted a missing required service\n' >&2
  exit 1
fi
: >"$fixture/packages/sleepy-shell/src/services/NiriService.qml"

assert_rejected() {
  local name=$1
  local relative_path=$2
  local payload=$3
  local probe="$fixture/$relative_path"

  printf '%s\n' "$payload" >"$probe"
  if bash "$contract" "$fixture" >/dev/null 2>&1; then
    rm -f "$probe"
    printf 'contract accepted forbidden probe: %s\n' "$name" >&2
    return 1
  fi
  rm -f "$probe"
}

shell_probe=packages/sleepy-shell/src/Probe.qml
widget_probe=packages/sleepy-shell/src/widgets/Probe.qml

assert_rejected mutable-settings-path "$shell_probe" \
  'QtObject { property string path: Quickshell.configDir + "/sleepy/settings.json" }'
assert_rejected shell-file-view "$shell_probe" \
  'FileView { path: settingsPath }'
assert_rejected shell-file-view-adapter "$shell_probe" \
  'FileViewAdapter { }'
assert_rejected shell-json-adapter "$shell_probe" \
  'JsonAdapter { }'
assert_rejected shell-write-adapter "$shell_probe" \
  'Component.onCompleted: settingsFile.writeAdapter()'
assert_rejected shell-set-text "$shell_probe" \
  'Component.onCompleted: settingsFile.setText("{}")'
assert_rejected shell-multiline-file-write "$shell_probe" \
  $'FileView\n{\n  path: settingsPath\n  Component.onCompleted: writeAdapter\n  ()\n}'
assert_rejected qt-settings-adapter "$shell_probe" \
  'import Qt.labs.settings'
assert_rejected unmanaged-force modules/Probe.nix \
  'home.file."probe".force = true;'

assert_rejected widget-process "$widget_probe" \
  'Process { command: ["true"] }'
assert_rejected widget-exec-detached "$widget_probe" \
  'Component.onCompleted: Quickshell.execDetached(["true"])'
assert_rejected widget-io-import "$widget_probe" \
  'import Quickshell.Io'
assert_rejected widget-json-parse "$widget_probe" \
  'QtObject { property var value: JSON.parse("{}") }'
assert_rejected widget-file-view "$widget_probe" \
  'FileView { path: "/tmp/probe" }'
assert_rejected widget-file-view-adapter "$widget_probe" \
  'FileViewAdapter { }'
assert_rejected widget-json-adapter "$widget_probe" \
  'JsonAdapter { }'

bash "$contract" "$repo_root"
rg -Fq 'home.packages = [config.sleepy.shellPackage];' \
  "$repo_root/modules/home/quickshell/default.nix"
rg -Fq 'ExecStart = "${config.sleepy.shellPackage}/bin/sleepy-shell";' \
  "$repo_root/modules/home/quickshell/default.nix"
printf 'quickshell contract self-test: ok\n'
