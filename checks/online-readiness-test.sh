#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/modules/home/session/online-reconcile.sh"
fixture=$(mktemp -d /tmp/sleepy-online-readiness.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
socket="$fixture/niri.sock"
fixture_bash=$(command -v bash)

printf '#!%s\n' "$fixture_bash" >"$fixture/systemctl"
cat >>"$fixture/systemctl" <<'EOF'
test "$*" = '--user show-environment'
printf 'NIRI_SOCKET=%s\n' "${SOCKET_PATH:?}"
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/socket-ready"
cat >>"$fixture/socket-ready" <<'EOF'
test "$1" = "${SOCKET_PATH:?}"
test -f "${READY_MARKER:?}"
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/sleep"
cat >>"$fixture/sleep" <<'EOF'
printf '.\n' >>"${SLEEP_MARKER:?}"
if test "${CREATE_SOCKET:-0}" = 1 && ! test -f "${READY_MARKER:?}"; then
  : >"$READY_MARKER"
fi
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/sleepyctl"
cat >>"$fixture/sleepyctl" <<'EOF'
test "$*" = 'bindings reconcile --online-required'
"${SLEEPY_SOCKET_READY_CHECK:?}" "${NIRI_SOCKET:?}"
count=0
test ! -f "${CALL_COUNT:?}" || count=$(cat "$CALL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$CALL_COUNT"
if test "$count" -lt "${SUCCEED_ON_CALL:-1}"; then
  printf '%s\n' '{"error":{"code":"niri_unavailable","message":"socket is stale"}}' >&2
  exit 1
fi
printf '%s\n' '{"status":"committed"}'
EOF
chmod +x "$fixture/systemctl" "$fixture/socket-ready" "$fixture/sleep" "$fixture/sleepyctl"
for fixture_executable in systemctl socket-ready sleep sleepyctl; do
  test "$(sed -n '1s/^#!//p' "$fixture/$fixture_executable")" = "$fixture_bash"
  test -x "$fixture_bash"
done

# A non-empty but stale manager environment is not readiness. No CLI call is
# made, the loop is bounded, and failure remains a typed document.
if SLEEPYCTL="$fixture/sleepyctl" \
  SLEEPY_SYSTEMCTL="$fixture/systemctl" \
  SLEEPY_SLEEP="$fixture/sleep" \
  SLEEPY_SOCKET_READY_CHECK="$fixture/socket-ready" \
  SLEEPY_SOCKET_ATTEMPTS=3 \
  SOCKET_PATH="$socket" \
  READY_MARKER="$fixture/ready" \
  SLEEP_MARKER="$fixture/stale-sleeps" \
  CALL_COUNT="$fixture/stale-calls" \
  bash "$script" 2>"$fixture/stale-error"; then
  printf 'online readiness accepted a stale NIRI_SOCKET\n' >&2
  exit 1
fi
test "$(wc -l <"$fixture/stale-sleeps")" -eq 3
test ! -e "$fixture/stale-calls"
grep -F '"code":"niri_unavailable"' "$fixture/stale-error"

# A usable socket whose online reconcile remains unavailable is retried to the
# same bound. The final typed CLI error is preserved and the service fails, so
# Quickshell's Requires dependency remains blocked.
: >"$fixture/ready"
if SOCKET_PATH="$socket" \
  SUCCEED_ON_CALL=99 \
  SLEEPYCTL="$fixture/sleepyctl" \
  SLEEPY_SYSTEMCTL="$fixture/systemctl" \
  SLEEPY_SLEEP="$fixture/sleep" \
  SLEEPY_SOCKET_READY_CHECK="$fixture/socket-ready" \
  SLEEPY_SOCKET_ATTEMPTS=2 \
  READY_MARKER="$fixture/ready" \
  SLEEP_MARKER="$fixture/failing-sleeps" \
  CALL_COUNT="$fixture/failing-calls" \
  bash "$script" 2>"$fixture/failing-error"; then
  printf 'online readiness accepted repeated typed CLI failures\n' >&2
  exit 1
fi
test "$(cat "$fixture/failing-calls")" -eq 2
test "$(wc -l <"$fixture/failing-sleeps")" -eq 2
grep -F '"code":"niri_unavailable"' "$fixture/failing-error"
rm -f "$fixture/ready"

# The socket appears after the stale snapshot. The first realistic CLI probe
# still fails, then the bounded loop retries and succeeds.
SOCKET_PATH="$socket" \
  CREATE_SOCKET=1 \
  SUCCEED_ON_CALL=2 \
  SLEEPYCTL="$fixture/sleepyctl" \
  SLEEPY_SYSTEMCTL="$fixture/systemctl" \
  SLEEPY_SLEEP="$fixture/sleep" \
  SLEEPY_SOCKET_READY_CHECK="$fixture/socket-ready" \
  SLEEPY_SOCKET_ATTEMPTS=5 \
  READY_MARKER="$fixture/ready" \
  SLEEP_MARKER="$fixture/ready-sleeps" \
  CALL_COUNT="$fixture/ready-calls" \
  bash "$script" >"$fixture/ready-output"
test "$(cat "$fixture/ready-calls")" -eq 2
test "$(wc -l <"$fixture/ready-sleeps")" -eq 2
grep -F '"status":"committed"' "$fixture/ready-output"

printf 'online readiness self-test: ok\n'
