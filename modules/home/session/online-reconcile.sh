set -euo pipefail

sleepyctl=${SLEEPYCTL:?SLEEPYCTL must name the pinned sleepyctl executable}
systemctl=${SLEEPY_SYSTEMCTL:-systemctl}
sleep_command=${SLEEPY_SLEEP:-sleep}
max_attempts=${SLEEPY_SOCKET_ATTEMPTS:-150}

socket_is_ready() {
  if test -n "${SLEEPY_SOCKET_READY_CHECK:-}"; then
    "$SLEEPY_SOCKET_READY_CHECK" "$1"
  else
    test -S "$1"
  fi
}

case "$max_attempts" in
  '' | *[!0-9]* | 0)
    printf 'Sleepy online reconciliation has an invalid attempt bound\n' >&2
    exit 2
    ;;
esac

attempt=0
last_error=
while test "$attempt" -lt "$max_attempts"; do
  niri_socket=
  while IFS= read -r environment_entry; do
    case "$environment_entry" in
      NIRI_SOCKET=*) niri_socket=${environment_entry#NIRI_SOCKET=} ;;
    esac
  done <<EOF
$("$systemctl" --user show-environment)
EOF
  if test -n "$niri_socket" && socket_is_ready "$niri_socket"; then
    export NIRI_SOCKET="$niri_socket"
    if reconcile_output=$("$sleepyctl" bindings reconcile --online-required 2>&1); then
      printf '%s\n' "$reconcile_output"
      exit 0
    fi
    last_error=$reconcile_output
  fi
  attempt=$((attempt + 1))
  "$sleep_command" 0.1
done

if test -n "$last_error"; then
  printf '%s\n' "$last_error" >&2
else
  printf '%s\n' '{"error":{"code":"niri_unavailable","message":"Niri socket did not become ready before the bounded deadline"}}' >&2
fi
exit 1
