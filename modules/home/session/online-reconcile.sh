set -euo pipefail

sleepyctl=${SLEEPYCTL:?SLEEPYCTL must name the pinned sleepyctl executable}
jq=${SLEEPY_JQ:?SLEEPY_JQ must name the pinned jq executable}
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
      if initialize_output=$("$sleepyctl" bindings initialize 2>&1); then
        if printf '%s\n' "$initialize_output" | "$jq" -e '
          type == "object"
          and keys == ["activePresetId", "status"]
          and .status == "committed"
          and (.activePresetId | type == "string" and length > 0)
        ' >/dev/null 2>&1; then
          printf '%s\n' "$initialize_output"
          exit 0
        fi

        if printf '%s\n' "$initialize_output" | "$jq" -e '
          type == "object"
          and keys == ["activePresetId", "status"]
          and (.status == "committed"
            or .status == "rolledBackConfirmed"
            or .status == "commitStateUnknown"
            or .status == "reloadPending")
          and (.activePresetId | type == "string" and length > 0)
        ' >/dev/null 2>&1; then
          # $report below is a jq variable, not a shell variable.
          # shellcheck disable=SC2016
          last_error=$("$jq" -cn --argjson report "$initialize_output" '
            {error: {
              code: "binding_initialize_uncommitted",
              message: "Binding initialization did not reach a committed state",
              details: {applyReport: $report}
            }}
          ')
        else
          # $output below is a jq variable, not a shell variable.
          # shellcheck disable=SC2016
          last_error=$("$jq" -cn --arg output "$initialize_output" '
            {error: {
              code: "binding_initialize_invalid_report",
              message: "Binding initialization returned an invalid ApplyReport",
              details: {output: $output}
            }}
          ')
        fi
      else
        last_error=$initialize_output
      fi
    else
      last_error=$reconcile_output
    fi
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
