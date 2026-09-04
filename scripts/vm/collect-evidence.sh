#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  printf 'usage: %s --domain Sleepy --run-dir /absolute/new-directory --label kebab-case --redacted-framebuffer /absolute/file.png --redacted-runtime /absolute/file.json --confirm-redacted --reviewer ID --delete-after YYYY-MM-DD\n' "${0##*/}" >&2
  exit 2
}

domain=
run_dir=
label=
redacted_framebuffer=
redacted_runtime=
reviewer=
delete_after=
redaction_confirmed=0
while test "$#" -gt 0; do
  case "$1" in
    --domain | --run-dir | --label | --redacted-framebuffer | --redacted-runtime | --reviewer | --delete-after)
      test "$#" -ge 2 || usage
      case "$1" in
        --domain) domain=$2 ;;
        --run-dir) run_dir=$2 ;;
        --label) label=$2 ;;
        --redacted-framebuffer) redacted_framebuffer=$2 ;;
        --redacted-runtime) redacted_runtime=$2 ;;
        --reviewer) reviewer=$2 ;;
        --delete-after) delete_after=$2 ;;
      esac
      shift 2
      ;;
    --confirm-redacted)
      redaction_confirmed=1
      shift
      ;;
    *) usage ;;
  esac
done

virsh_system() {
  command virsh --connect qemu:///system "$@"
}

test "$domain" = Sleepy || {
  printf 'collect evidence: refusing domain other than exact target Sleepy\n' >&2
  exit 2
}
[[ "$label" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
  printf 'collect evidence: label must contain only lowercase letters, digits, and hyphens\n' >&2
  exit 2
}
if test "${#label}" -gt 48 || [[ "$label" == *--* ]] || [[ "$label" == *- ]]; then
  printf 'collect evidence: invalid or overlong label\n' >&2
  exit 2
fi
[[ "$reviewer" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || {
  printf 'collect evidence: reviewer must be a short identifier\n' >&2
  exit 2
}
test "${#reviewer}" -le 64 || {
  printf 'collect evidence: reviewer identifier is too long\n' >&2
  exit 2
}
[[ "$delete_after" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
  printf 'collect evidence: deletion date must use YYYY-MM-DD\n' >&2
  exit 2
}
test "$redaction_confirmed" = 1 || {
  printf 'collect evidence: explicit --confirm-redacted acknowledgement is required\n' >&2
  exit 2
}

for command_name in date grep install jq mkdir pngcheck realpath sed sha256sum stat tr virsh; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'collect evidence: required command not found: %s\n' "$command_name" >&2
    exit 127
  }
done
date -d "$delete_after" '+%F' | grep -Fx "$delete_after" >/dev/null || {
  printf 'collect evidence: invalid deletion date\n' >&2
  exit 2
}
test "$(date -d "$delete_after" +%s)" -gt "$(date +%s)" || {
  printf 'collect evidence: deletion date must be in the future\n' >&2
  exit 2
}

for input_path in "$run_dir" "$redacted_framebuffer" "$redacted_runtime"; do
  case "$input_path" in
    /*) ;;
    *)
      printf 'collect evidence: all paths must be absolute\n' >&2
      exit 2
      ;;
  esac
done
for input_path in "$redacted_framebuffer" "$redacted_runtime"; do
  test -f "$input_path" && test ! -L "$input_path" || {
    printf 'collect evidence: redacted input must be a regular non-symlink file: %s\n' "$input_path" >&2
    exit 1
  }
  test "$(stat -c %a "$input_path")" = 600 || {
    printf 'collect evidence: redacted input must be mode 0600: %s\n' "$input_path" >&2
    exit 1
  }
done
redacted_framebuffer=$(realpath -e -- "$redacted_framebuffer")
redacted_runtime=$(realpath -e -- "$redacted_runtime")
if ! pngcheck -q "$redacted_framebuffer" >/dev/null 2>&1; then
  printf 'collect evidence: framebuffer input is not a PNG image\n' >&2
  exit 1
fi

hex40='^[0-9a-f]{40}$'
jq -e --arg hex40 "$hex40" '
  .schemaVersion == 1 and .redacted == true and
  (.candidate.system | startswith("/nix/store/") and contains("-nixos-system-sleepy")) and
  (.candidate.rootCommit | test($hex40)) and
  ([.candidate.components.sleepySdk, .candidate.components.sleepySession,
    .candidate.components.sleepyArtwork, .candidate.components.sleepyDesktop]
    | all(test($hex40))) and
  .services == {
    sleepySession: "active",
    sleepyShell: "active",
    sleepyLocker: "active",
    failedUserUnits: 0,
    failedSystemUnits: 0
  } and
  .compositor == {hyprlandSocket: true, niriProcess: false} and
  .snapshot.schemaVersion == 3 and .snapshot.type == "fullSnapshot" and
  (.snapshot.generation | type == "number" and . >= 1 and floor == .) and
  .functional == {
    launcher: true,
    workspaces: true,
    notifications: true,
    appearance: true,
    network: true,
    audio: true,
    degradedHardware: true,
    daemonRestartRecovery: true,
    shellRestartRecovery: true,
    lockCrashCases: true,
    suspendResume: true,
    logoutToRegreet: true,
    portalFileChooser: true,
    portalScreencast: true,
    priorGenerationBoot: true,
    returnToCandidate: true
  } and
  ([.. | objects | keys[] | ascii_downcase]
    | all(test("password|passwd|secret|credential|ssid|notificationtext|device(name)?|documentpath|journal") | not)) and
  ([.. | strings]
    | all(test("(^|[[:space:]])/home/|/run/user/|BEGIN [A-Z ]*PRIVATE KEY") | not))
' "$redacted_runtime" >/dev/null || {
  printf 'collect evidence: runtime evidence is incomplete, unredacted, or failed acceptance\n' >&2
  exit 1
}

run_parent=$(dirname -- "$run_dir")
run_name=$(basename -- "$run_dir")
case "$run_name" in
  '' | '.' | '..' | *[!A-Za-z0-9._-]*)
    printf 'collect evidence: unsafe run-directory basename\n' >&2
    exit 2
    ;;
esac
test -d "$run_parent" && test ! -L "$run_parent" || {
  printf 'collect evidence: run-directory parent must be an existing non-symlink directory\n' >&2
  exit 1
}
run_parent=$(realpath -e -- "$run_parent")
run_dir="$run_parent/$run_name"
if test -e "$run_dir" || test -L "$run_dir"; then
  printf 'collect evidence: refusing to replace run directory: %s\n' "$run_dir" >&2
  exit 1
fi

domain_uuid=$(virsh_system domuuid "$domain")
case "$domain_uuid" in
  ????????-????-????-????-????????????) ;;
  *)
    printf 'collect evidence: invalid libvirt UUID\n' >&2
    exit 1
    ;;
esac
domain_state=$(virsh_system domstate "$domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
test "$domain_state" = running || {
  printf 'collect evidence: %s must be running, got: %s\n' "$domain" "$domain_state" >&2
  exit 1
}

mkdir -m 0700 -- "$run_dir"
install -m 0600 -- "$redacted_runtime" "$run_dir/runtime.json"
install -m 0600 -- "$redacted_framebuffer" "$run_dir/$label.png"

jq -n \
  --arg domain "$domain" \
  --arg uuid "$domain_uuid" \
  --arg label "$label" \
  --arg reviewer "$reviewer" \
  --arg deleteAfter "$delete_after" \
  '{
    schemaVersion: 1,
    kind: "sleepy-redacted-acceptance-evidence",
    domain: {name: $domain, uuid: $uuid, observedState: "running"},
    label: $label,
    reviewer: $reviewer,
    deleteAfter: $deleteAfter,
    redaction: {
      confirmed: true,
      excluded: ["credentials", "SSIDs", "notification text", "document paths", "device names", "raw journals"]
    },
    rawArtifactsRetained: false,
    artifacts: {runtime: "runtime.json", framebuffer: ($label + ".png")}
  }' >"$run_dir/evidence.json"
chmod 0600 "$run_dir/evidence.json"
(
  cd "$run_dir"
  sha256sum runtime.json "$label.png" evidence.json >checksums.sha256
)
chmod 0600 "$run_dir/checksums.sha256"
printf 'redacted evidence set; delete on the recorded retention date\n' >"$run_dir/evidence.complete"
chmod 0600 "$run_dir/evidence.complete"

printf '%s\n' "$run_dir"
