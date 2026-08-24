#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/modules/home/session/online-reconcile.sh"
fixture=$(mktemp -d /tmp/sleepy-online-readiness.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
socket="$fixture/niri.sock"
fixture_bash=$(command -v bash)
fixture_jq=$(command -v jq)

printf '#!%s\n' "$fixture_bash" >"$fixture/systemctl"
cat >>"$fixture/systemctl" <<'EOF'
test "$#" -eq 2
test "$1" = '--user'
test "$2" = 'show-environment'
printf 'NIRI_SOCKET=%s\n' "${SOCKET_PATH:?}"
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/socket-ready"
cat >>"$fixture/socket-ready" <<'EOF'
test "$#" -eq 1
test "$1" = "${SOCKET_PATH:?}"
test -f "${READY_MARKER:?}"
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/sleep"
cat >>"$fixture/sleep" <<'EOF'
test "$#" -eq 1
test "$1" = '0.1'
printf '.\n' >>"${SLEEP_MARKER:?}"
if test "${CREATE_SOCKET:-0}" = 1 && ! test -f "${READY_MARKER:?}"; then
  : >"$READY_MARKER"
fi
EOF
printf '#!%s\n' "$fixture_bash" >"$fixture/sleepyctl"
cat >>"$fixture/sleepyctl" <<'EOF'
for argument in "$@"; do
  printf '<%s>' "$argument" >>"${CALL_LOG:?}"
done
printf '\n' >>"$CALL_LOG"

case "$#:$1:${2:-}:${3:-}" in
  3:bindings:reconcile:--online-required)
    "${SLEEPY_SOCKET_READY_CHECK:?}" "${NIRI_SOCKET:?}"
    count=0
    test ! -f "${RECONCILE_COUNT:?}" || count=$(cat "$RECONCILE_COUNT")
    count=$((count + 1))
    printf '%s\n' "$count" >"$RECONCILE_COUNT"
    if test "$count" -lt "${RECONCILE_SUCCEED_ON_CALL:-1}"; then
      printf '%s\n' '{"error":{"code":"niri_unavailable","message":"socket is stale"}}' >&2
      exit 1
    fi
    printf '%s\n' "${RECONCILE_OUTPUT:-null}"
    ;;
  2:bindings:initialize:)
    "${SLEEPY_SOCKET_READY_CHECK:?}" "${NIRI_SOCKET:?}"
    count=0
    test ! -f "${INITIALIZE_COUNT:?}" || count=$(cat "$INITIALIZE_COUNT")
    count=$((count + 1))
    printf '%s\n' "$count" >"$INITIALIZE_COUNT"
    case "${INITIALIZE_MODE:-committed}" in
      committed)
        printf '%s\n' '{"status":"committed","activePresetId":"builtin.sleepy"}'
        ;;
      reloadPending)
        printf '%s\n' '{"status":"reloadPending","activePresetId":"builtin.sleepy"}'
        ;;
      commitStateUnknown)
        printf '%s\n' '{"status":"commitStateUnknown","activePresetId":"builtin.sleepy"}'
        ;;
      error)
        printf '%s\n' '{"error":{"code":"niri_unavailable","message":"initialize failed"}}' >&2
        exit 1
        ;;
      malformed)
        printf '%s\n' 'not-json'
        ;;
      extraField)
        printf '%s\n' '{"status":"committed","activePresetId":"builtin.sleepy","unexpected":true}'
        ;;
      emptyPreset)
        printf '%s\n' '{"status":"committed","activePresetId":""}'
        ;;
      committedLastStream)
        printf '%s\n' \
          '{"unexpected":true}' \
          '{"status":"committed","activePresetId":"builtin.sleepy"}'
        ;;
      committedFirstStream)
        printf '%s\n' \
          '{"status":"committed","activePresetId":"builtin.sleepy"}' \
          '{"unexpected":true}'
        ;;
      *) exit 64 ;;
    esac
    ;;
  *)
    printf 'unexpected sleepyctl argv\n' >&2
    exit 64
    ;;
esac
EOF
chmod +x "$fixture/systemctl" "$fixture/socket-ready" "$fixture/sleep" "$fixture/sleepyctl"
for fixture_executable in systemctl socket-ready sleep sleepyctl; do
  test "$(sed -n '1s/^#!//p' "$fixture/$fixture_executable")" = "$fixture_bash"
  test -x "$fixture_bash"
done

run_online() {
  local attempts=$1
  local ready_marker=$2
  local sleep_marker=$3
  local call_log=$4
  local reconcile_count=$5
  local initialize_count=$6
  shift 6
  env \
    SLEEPYCTL="$fixture/sleepyctl" \
    SLEEPY_JQ="$fixture_jq" \
    SLEEPY_SYSTEMCTL="$fixture/systemctl" \
    SLEEPY_SLEEP="$fixture/sleep" \
    SLEEPY_SOCKET_READY_CHECK="$fixture/socket-ready" \
    SLEEPY_SOCKET_ATTEMPTS="$attempts" \
    SOCKET_PATH="$socket" \
    READY_MARKER="$ready_marker" \
    SLEEP_MARKER="$sleep_marker" \
    CALL_LOG="$call_log" \
    RECONCILE_COUNT="$reconcile_count" \
    INITIALIZE_COUNT="$initialize_count" \
    "$@" \
    bash "$script"
}

# A non-empty but stale manager environment is not readiness. No CLI call is
# made, the loop is bounded, and failure remains a typed document.
if run_online 3 \
  "$fixture/stale-ready" \
  "$fixture/stale-sleeps" \
  "$fixture/stale-calls" \
  "$fixture/stale-reconciles" \
  "$fixture/stale-initializes" \
  2>"$fixture/stale-error"; then
  printf 'online readiness accepted a stale NIRI_SOCKET\n' >&2
  exit 1
fi
test "$(wc -l <"$fixture/stale-sleeps")" -eq 3
test ! -e "$fixture/stale-calls"
grep -F '"code":"niri_unavailable"' "$fixture/stale-error" >/dev/null

# No journal is a successful reconcile represented by JSON null. Readiness is
# confirmed only after initialize commits on the same attested socket.
: >"$fixture/no-journal-ready"
run_online 3 \
  "$fixture/no-journal-ready" \
  "$fixture/no-journal-sleeps" \
  "$fixture/no-journal-calls" \
  "$fixture/no-journal-reconciles" \
  "$fixture/no-journal-initializes" \
  >"$fixture/no-journal-output"
printf '%s\n' \
  '<bindings><reconcile><--online-required>' \
  '<bindings><initialize>' >"$fixture/no-journal-expected"
cmp "$fixture/no-journal-expected" "$fixture/no-journal-calls"
test "$(cat "$fixture/no-journal-reconciles")" -eq 1
test "$(cat "$fixture/no-journal-initializes")" -eq 1
test ! -e "$fixture/no-journal-sleeps"
test "$(cat "$fixture/no-journal-output")" = \
  '{"status":"committed","activePresetId":"builtin.sleepy"}'

# Reconcile failure is retried to the same bound and initialize is never
# started, preserving the prerequisite ordering.
: >"$fixture/reconcile-failure-ready"
if run_online 2 \
  "$fixture/reconcile-failure-ready" \
  "$fixture/reconcile-failure-sleeps" \
  "$fixture/reconcile-failure-calls" \
  "$fixture/reconcile-failure-reconciles" \
  "$fixture/reconcile-failure-initializes" \
  RECONCILE_SUCCEED_ON_CALL=99 \
  2>"$fixture/reconcile-failure-error"; then
  printf 'online readiness accepted repeated reconcile failures\n' >&2
  exit 1
fi
printf '%s\n' \
  '<bindings><reconcile><--online-required>' \
  '<bindings><reconcile><--online-required>' \
  >"$fixture/reconcile-failure-expected"
cmp "$fixture/reconcile-failure-expected" "$fixture/reconcile-failure-calls"
test "$(cat "$fixture/reconcile-failure-reconciles")" -eq 2
test ! -e "$fixture/reconcile-failure-initializes"
test "$(wc -l <"$fixture/reconcile-failure-sleeps")" -eq 2
grep -F '"code":"niri_unavailable"' "$fixture/reconcile-failure-error" >/dev/null

# A successful CLI exit is insufficient: every non-committed ApplyReport is
# retried to the bound and returned as a typed orchestration error.
for initialize_mode in reloadPending commitStateUnknown; do
  : >"$fixture/$initialize_mode-ready"
  if run_online 2 \
    "$fixture/$initialize_mode-ready" \
    "$fixture/$initialize_mode-sleeps" \
    "$fixture/$initialize_mode-calls" \
    "$fixture/$initialize_mode-reconciles" \
    "$fixture/$initialize_mode-initializes" \
    INITIALIZE_MODE="$initialize_mode" \
    2>"$fixture/$initialize_mode-error"; then
    printf 'online readiness accepted initialize status: %s\n' "$initialize_mode" >&2
    exit 1
  fi
  test "$(cat "$fixture/$initialize_mode-reconciles")" -eq 2
  test "$(cat "$fixture/$initialize_mode-initializes")" -eq 2
  test "$(wc -l <"$fixture/$initialize_mode-calls")" -eq 4
  test "$(sed -n '1p;3p' "$fixture/$initialize_mode-calls" | uniq)" = \
    '<bindings><reconcile><--online-required>'
  test "$(sed -n '2p;4p' "$fixture/$initialize_mode-calls" | uniq)" = \
    '<bindings><initialize>'
  test "$(wc -l <"$fixture/$initialize_mode-sleeps")" -eq 2
  grep -F '"code":"binding_initialize_uncommitted"' \
    "$fixture/$initialize_mode-error" >/dev/null
  grep -F "\"status\":\"$initialize_mode\"" \
    "$fixture/$initialize_mode-error" >/dev/null
done

# A typed initialize CLI failure is retried and its final error is preserved.
: >"$fixture/initialize-error-ready"
if run_online 2 \
  "$fixture/initialize-error-ready" \
  "$fixture/initialize-error-sleeps" \
  "$fixture/initialize-error-calls" \
  "$fixture/initialize-error-reconciles" \
  "$fixture/initialize-error-initializes" \
  INITIALIZE_MODE=error \
  2>"$fixture/initialize-error-output"; then
  printf 'online readiness accepted repeated initialize errors\n' >&2
  exit 1
fi
test "$(cat "$fixture/initialize-error-reconciles")" -eq 2
test "$(cat "$fixture/initialize-error-initializes")" -eq 2
test "$(wc -l <"$fixture/initialize-error-sleeps")" -eq 2
grep -F '"code":"niri_unavailable"' "$fixture/initialize-error-output" >/dev/null

# ApplyReport validation is strict: malformed JSON, unknown fields, an empty
# active preset, and multi-document streams cannot open the graphical-session
# dependency gate. Both stream orders are covered because jq otherwise derives
# its exit status from the final document.
for initialize_mode in \
  malformed \
  extraField \
  emptyPreset \
  committedLastStream \
  committedFirstStream; do
  : >"$fixture/strict-$initialize_mode-ready"
  if run_online 1 \
    "$fixture/strict-$initialize_mode-ready" \
    "$fixture/strict-$initialize_mode-sleeps" \
    "$fixture/strict-$initialize_mode-calls" \
    "$fixture/strict-$initialize_mode-reconciles" \
    "$fixture/strict-$initialize_mode-initializes" \
    INITIALIZE_MODE="$initialize_mode" \
    2>"$fixture/strict-$initialize_mode-error"; then
    printf 'online readiness accepted invalid initialize report: %s\n' \
      "$initialize_mode" >&2
    exit 1
  fi
  test "$(cat "$fixture/strict-$initialize_mode-reconciles")" -eq 1
  test "$(cat "$fixture/strict-$initialize_mode-initializes")" -eq 1
  "$fixture_jq" -e '
    .error.code == "binding_initialize_invalid_report"
    and (.error.details.output | type == "string" and length > 0)
  ' "$fixture/strict-$initialize_mode-error" >/dev/null

  case "$initialize_mode" in
    committedLastStream)
      expected_diagnostic=$(printf '%s\n' \
        '{"unexpected":true}' \
        '{"status":"committed","activePresetId":"builtin.sleepy"}')
      # $expected below is a jq variable, not a shell variable.
      # shellcheck disable=SC2016
      "$fixture_jq" -e --arg expected "$expected_diagnostic" \
        '.error.details.output == $expected' \
        "$fixture/strict-$initialize_mode-error" >/dev/null
      ;;
    committedFirstStream)
      expected_diagnostic=$(printf '%s\n' \
        '{"status":"committed","activePresetId":"builtin.sleepy"}' \
        '{"unexpected":true}')
      # $expected below is a jq variable, not a shell variable.
      # shellcheck disable=SC2016
      "$fixture_jq" -e --arg expected "$expected_diagnostic" \
        '.error.details.output == $expected' \
        "$fixture/strict-$initialize_mode-error" >/dev/null
      ;;
  esac
done

# The socket appears after the stale snapshot. The first realistic reconcile
# still fails, then the bounded loop retries the exact ordered pair and exits
# only when initialize commits.
run_online 5 \
  "$fixture/delayed-ready" \
  "$fixture/delayed-sleeps" \
  "$fixture/delayed-calls" \
  "$fixture/delayed-reconciles" \
  "$fixture/delayed-initializes" \
  CREATE_SOCKET=1 \
  RECONCILE_SUCCEED_ON_CALL=2 \
  >"$fixture/delayed-output"
printf '%s\n' \
  '<bindings><reconcile><--online-required>' \
  '<bindings><reconcile><--online-required>' \
  '<bindings><initialize>' >"$fixture/delayed-expected"
cmp "$fixture/delayed-expected" "$fixture/delayed-calls"
test "$(cat "$fixture/delayed-reconciles")" -eq 2
test "$(cat "$fixture/delayed-initializes")" -eq 1
test "$(wc -l <"$fixture/delayed-sleeps")" -eq 2
test "$(cat "$fixture/delayed-output")" = \
  '{"status":"committed","activePresetId":"builtin.sleepy"}'

printf 'online readiness self-test: ok\n'
