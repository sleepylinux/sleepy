#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  printf 'quickshell contract: required command not found: rg\n' >&2
  exit 127
fi

repo_root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
shell_root="$repo_root/packages/sleepy-shell/src"
widgets_root="$shell_root/widgets"

test -f "$shell_root/services/NiriService.qml"
test -f "$shell_root/modules/panel/Panel.qml"

if rg -n -U 'force[[:space:]]*=' "$repo_root/packages" "$repo_root/modules"; then
  exit 1
fi

if rg -n -U \
  'settings[.]json|Qt[.]labs[.]settings|QtQuick[.]LocalStorage|Settings[[:space:]]*\{|LocalStorage[[:space:]]*\{|FileView(Internal|Adapter)?[[:space:]]*\{|JsonAdapter[[:space:]]*\{|writeAdapter[[:space:]]*\(|set(Text|Data)[[:space:]]*\(' \
  -g '*.qml' "$shell_root"; then
  exit 1
fi

if rg -n -U \
  'Process[[:space:]]*\{|execDetached|Quickshell[.]Io|JSON[[:space:]]*[.][[:space:]]*parse|FileView(Internal|Adapter)?[[:space:]]*\{|JsonAdapter[[:space:]]*\{' \
  -g '*.qml' "$widgets_root"; then
  exit 1
fi
