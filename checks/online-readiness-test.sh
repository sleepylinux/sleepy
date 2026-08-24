#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/modules/home/session/online-reconcile.sh"
fixture=$(mktemp -d /tmp/sleepy-online-readiness.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/systemctl-empty" <<'EOF'
#!/usr/bin/env bash
test "$*" = '--user show-environment'
printf 'WAYLAND_DISPLAY=wayland-1\n'
EOF
cat >"$fixture/systemctl-ready" <<'EOF'
#!/usr/bin/env bash
test "$*" = '--user show-environment'
printf 'NIRI_SOCKET=/run/user/1000/niri.sock\n'
EOF
cat >"$fixture/sleep" <<'EOF'
#!/usr/bin/env bash
printf '.\n' >>"${SLEEP_MARKER:?}"
EOF
cat >"$fixture/sleepyctl" <<'EOF'
#!/usr/bin/env bash
test "$*" = 'bindings reconcile --online-required'
test "${NIRI_SOCKET:-}" = '/run/user/1000/niri.sock'
printf 'called\n' >"${SLEEPYCTL_MARKER:?}"
EOF
chmod +x "$fixture"/*

if SLEEPYCTL="$fixture/sleepyctl" \
  SLEEPY_SYSTEMCTL="$fixture/systemctl-empty" \
  SLEEPY_SLEEP="$fixture/sleep" \
  SLEEPY_SOCKET_ATTEMPTS=3 \
  SLEEP_MARKER="$fixture/sleeps" \
  SLEEPYCTL_MARKER="$fixture/called" \
  bash "$script" 2>"$fixture/timeout-error"; then
  printf 'online readiness accepted a permanently missing NIRI_SOCKET\n' >&2
  exit 1
fi
test "$(wc -l <"$fixture/sleeps")" -eq 3
grep -F 'timed out waiting for NIRI_SOCKET' "$fixture/timeout-error"
test ! -e "$fixture/called"

SLEEPYCTL="$fixture/sleepyctl" \
  SLEEPY_SYSTEMCTL="$fixture/systemctl-ready" \
  SLEEPY_SLEEP="$fixture/sleep" \
  SLEEPY_SOCKET_ATTEMPTS=3 \
  SLEEP_MARKER="$fixture/sleeps" \
  SLEEPYCTL_MARKER="$fixture/called" \
  bash "$script"
test -f "$fixture/called"

printf 'online readiness self-test: ok\n'
