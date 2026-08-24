set -euo pipefail

sleepyctl=${SLEEPYCTL:?SLEEPYCTL must name the pinned sleepyctl executable}
systemctl=${SLEEPY_SYSTEMCTL:-systemctl}
sleep_command=${SLEEPY_SLEEP:-sleep}
max_attempts=${SLEEPY_SOCKET_ATTEMPTS:-150}

case "$max_attempts" in
  '' | *[!0-9]* | 0)
    printf 'Sleepy online reconciliation has an invalid attempt bound\n' >&2
    exit 2
    ;;
esac

attempt=0
while test "$attempt" -lt "$max_attempts"; do
  niri_socket=
  while IFS= read -r environment_entry; do
    case "$environment_entry" in
      NIRI_SOCKET=*) niri_socket=${environment_entry#NIRI_SOCKET=} ;;
    esac
  done <<EOF
$("$systemctl" --user show-environment)
EOF
  if test -n "$niri_socket"; then
    export NIRI_SOCKET="$niri_socket"
    exec "$sleepyctl" bindings reconcile --online-required
  fi
  attempt=$((attempt + 1))
  "$sleep_command" 0.1
done

printf 'Sleepy online binding reconciliation timed out waiting for NIRI_SOCKET\n' >&2
exit 1
