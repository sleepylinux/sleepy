#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/bindings-policy.sh"
fixture=$(mktemp -d /tmp/sleepy-bindings-policy.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/core.kdl" <<'EOF'
binds {
    Mod+Shift+Escape { spawn "ghostty"; }
}
EOF
cat >"$fixture/generated.kdl" <<'EOF'
binds {
    Mod+Return { spawn "ghostty"; }
    Mod+D { spawn "fuzzel"; }
    Mod+C { spawn "quickshell" "ipc" "--config" "sleepy" "call" "sleepy" "toggleControlCenter"; }
    Mod+Ctrl+R { spawn "quickshell" "ipc" "--config" "sleepy" "call" "sleepy" "requestSessionAction" "reboot"; }
    Mod+P { spawn "quickshell" "ipc" "--config" "sleepy" "call" "sleepy" "openPowerMenu"; }
    XF86AudioPlay { spawn "playerctl" "play-pause"; }
}
EOF
bash "$contract" "$fixture/core.kdl" "$fixture/generated.kdl"

assert_rejected() {
  local name=$1 file=$2 text=$3
  cp "$fixture/core.kdl" "$fixture/$name-core.kdl"
  cp "$fixture/generated.kdl" "$fixture/$name-generated.kdl"
  printf '%s\n' "$text" >>"$fixture/$name-$file.kdl"
  if bash "$contract" "$fixture/$name-core.kdl" "$fixture/$name-generated.kdl" >/dev/null 2>&1; then
    printf 'bindings policy accepted invalid fixture: %s\n' "$name" >&2
    return 1
  fi
}

assert_rejected core-normal core 'XF86AudioMute { spawn "wpctl"; }'
assert_rejected core-function-key core 'F1 { spawn "ghostty"; }'
assert_rejected duplicate-chord generated 'Mod+C { spawn "ghostty"; }'
assert_rejected direct-poweroff generated 'Mod+X { spawn "systemctl" "poweroff"; }'
assert_rejected direct-reboot generated 'Mod+X { spawn "reboot"; }'
assert_rejected native-quit generated 'Mod+X { quit; }'

printf 'bindings policy self-test: ok\n'
