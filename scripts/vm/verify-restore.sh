#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  printf 'usage: %s --bundle /absolute/bundle --domain Sleepy --verification-domain Sleepy-restore-verification\n' "${0##*/}" >&2
  exit 2
}

bundle=
domain=
verification_domain=
while test "$#" -gt 0; do
  case "$1" in
    --bundle)
      test "$#" -ge 2 || usage
      bundle=$2
      shift 2
      ;;
    --domain)
      test "$#" -ge 2 || usage
      domain=$2
      shift 2
      ;;
    --verification-domain)
      test "$#" -ge 2 || usage
      verification_domain=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

virsh_system() {
  command virsh --connect qemu:///system "$@"
}

test "$domain" = Sleepy || {
  printf 'verify restore: protected domain must be exact target Sleepy\n' >&2
  exit 2
}
test "$verification_domain" = Sleepy-restore-verification || {
  printf 'verify restore: verification domain must be exact isolated name Sleepy-restore-verification\n' >&2
  exit 2
}
case "$bundle" in
  /*) ;;
  *)
    printf 'verify restore: bundle path must be absolute\n' >&2
    exit 2
    ;;
esac

for command_name in base64 cp grep jq mktemp python3 qemu-img realpath sed seq sha256sum sleep stat tr virsh; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'verify restore: required command not found: %s\n' "$command_name" >&2
    exit 127
  }
done

test -d "$bundle" && test ! -L "$bundle" || {
  printf 'verify restore: bundle must be a non-symlink directory\n' >&2
  exit 1
}
bundle=$(realpath -e -- "$bundle")
test "$(stat -c %a "$bundle")" = 700 || {
  printf 'verify restore: bundle directory must be mode 0700\n' >&2
  exit 1
}
for artifact in domain.xml nvram.fd disk.qcow2 backing-chain.json copy-info.json disk-check.json manifest.json checksums.sha256 bundle.complete; do
  test -f "$bundle/$artifact" && test ! -L "$bundle/$artifact" || {
    printf 'verify restore: missing regular artifact %s\n' "$artifact" >&2
    exit 1
  }
  test "$(stat -c %a "$bundle/$artifact")" = 600 || {
    printf 'verify restore: artifact must be mode 0600: %s\n' "$artifact" >&2
    exit 1
  }
done

# Integrity must be proven before the first libvirt query or mutation.
(cd "$bundle" && sha256sum --check checksums.sha256 >/dev/null)
jq -e --arg domain "$domain" '
  .schemaVersion == 1 and
  .kind == "sleepy-offline-rollback-bundle" and
  .completed == true and
  .domain.name == $domain and
  .domain.capturedState == "shut off" and
  (.domain.uuid | type == "string") and
  (.expectedSystem | startswith("/nix/store/") and contains("-nixos-system-sleepy")) and
  .disk.originalFormat == "qcow2" and
  .disk.copyFormat == "qcow2" and
  .disk.copyIsFlattened == true and
  .artifacts == {
    xml: "domain.xml",
    nvram: "nvram.fd",
    disk: "disk.qcow2",
    backingChain: "backing-chain.json",
    copyInfo: "copy-info.json",
    diskCheck: "disk-check.json"
  }
' "$bundle/manifest.json" >/dev/null
qemu-img check --output=json "$bundle/disk.qcow2" | jq -e '
  (.corruptions // 0) == 0 and (.leaks // 0) == 0 and (."check-errors" // 0) == 0
' >/dev/null
report="$bundle/restore-verification.json"
if test -e "$report" || test -L "$report"; then
  printf 'verify restore: refusing to replace existing verification report\n' >&2
  exit 1
fi

if virsh_system dominfo "$verification_domain" >/dev/null 2>&1; then
  printf 'verify restore: refusing to replace existing verification domain\n' >&2
  exit 1
fi
expected_uuid=$(jq -r '.domain.uuid' "$bundle/manifest.json")
expected_system=$(jq -r '.expectedSystem' "$bundle/manifest.json")
test "$(virsh_system domuuid "$domain")" = "$expected_uuid" || {
  printf 'verify restore: protected domain UUID does not match the captured bundle\n' >&2
  exit 1
}
test "$(virsh_system domstate "$domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" = 'shut off' || {
  printf 'verify restore: protected domain must remain shut off\n' >&2
  exit 1
}

work_parent=$(dirname -- "$bundle")
work_dir=$(mktemp -d "$work_parent/.sleepy-restore-verification.XXXXXX")
chmod 0700 "$work_dir"
defined=0
verification_uuid=
protected_guard_pid=
protected_event_pid=
protected_guard_stop="$work_dir/protected-guard.stop"
protected_guard_failure="$work_dir/protected-guard.failed"
protected_event_log="$work_dir/protected-events.log"

assert_protected_identity_offline() {
  local observed_uuid observed_state
  observed_uuid=$(virsh_system domuuid "$domain" 2>/dev/null || true)
  observed_state=$(virsh_system domstate "$domain" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
  test "$observed_uuid" = "$expected_uuid" && test "$observed_state" = 'shut off'
}

protected_guard() {
  while test ! -e "$protected_guard_stop"; do
    if ! assert_protected_identity_offline; then
      printf 'protected domain identity or offline state changed\n' >"$protected_guard_failure"
      return 1
    fi
    sleep 1
  done
}

check_protected_guard() {
  if ! test -n "$protected_event_pid" ||
    ! kill -0 "$protected_event_pid" 2>/dev/null ||
    test -e "$protected_guard_failure" ||
    grep -Eiq 'started|resumed' "$protected_event_log" 2>/dev/null ||
    ! assert_protected_identity_offline; then
    printf 'verify restore: protected domain identity changed or it started during the drill\n' >&2
    return 1
  fi
}

stop_protected_guard() {
  if test -n "$protected_guard_pid"; then
    : >"$protected_guard_stop"
    wait "$protected_guard_pid" || true
    protected_guard_pid=
  fi
  if test -n "$protected_event_pid"; then
    kill "$protected_event_pid" 2>/dev/null || true
    wait "$protected_event_pid" 2>/dev/null || true
    protected_event_pid=
  fi
}

cleanup() {
  local cleanup_status=0
  stop_protected_guard
  if test "$defined" = 1; then
    current_uuid=$(virsh_system domuuid "$verification_domain" 2>/dev/null || true)
    if test -n "$verification_uuid" && test "$current_uuid" = "$verification_uuid"; then
      current_state=$(virsh_system domstate "$verification_domain" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
      if test "$current_state" != 'shut off'; then
        virsh_system destroy "$verification_domain" >/dev/null 2>&1 || cleanup_status=1
      fi
      virsh_system undefine "$verification_domain" --nvram >/dev/null 2>&1 || cleanup_status=1
    else
      printf 'verify restore: refusing cleanup after verification-domain identity drift\n' >&2
      cleanup_status=1
    fi
  fi
  rm -f -- "$work_dir/domain.xml" "$work_dir/disk.qcow2" "$work_dir/nvram.fd" \
    "$protected_guard_stop" "$protected_guard_failure"
  rm -f -- "$protected_event_log"
  rmdir -- "$work_dir" 2>/dev/null || cleanup_status=1
  return "$cleanup_status"
}
on_exit() {
  local exit_status=$?
  trap - EXIT HUP INT TERM
  if ! cleanup; then
    printf 'verify restore: FAILED to remove the identity-checked temporary domain or files\n' >&2
    exit 1
  fi
  exit "$exit_status"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

protected_guard &
protected_guard_pid=$!
virsh_system event "$domain" --event lifecycle --loop --timestamp >"$protected_event_log" 2>&1 &
protected_event_pid=$!
sleep 1
check_protected_guard

cp --reflink=auto --sparse=always -- "$bundle/disk.qcow2" "$work_dir/disk.qcow2"
cp --reflink=auto --sparse=always -- "$bundle/nvram.fd" "$work_dir/nvram.fd"
chmod 0600 "$work_dir/disk.qcow2" "$work_dir/nvram.fd"
python3 - "$bundle/domain.xml" "$work_dir/domain.xml" "$verification_domain" "$work_dir/disk.qcow2" "$work_dir/nvram.fd" <<'PY'
import sys
import xml.etree.ElementTree as ET

source, target, name, disk_path, nvram_path = sys.argv[1:]
tree = ET.parse(source)
root = tree.getroot()
name_node = root.find("name")
if name_node is None or name_node.text != "Sleepy":
    raise SystemExit("baseline XML does not identify Sleepy")
name_node.text = name
for tag in ("uuid", "genid"):
    node = root.find(tag)
    if node is not None:
        root.remove(node)
nvram = root.find("./os/nvram")
disks = [
    disk for disk in root.findall("./devices/disk")
    if disk.get("device") == "disk" and disk.get("type") == "file"
]
if nvram is None or len(disks) != 1:
    raise SystemExit("baseline XML does not have the expected NVRAM and disk")
source_node = disks[0].find("source")
if source_node is None or "file" not in source_node.attrib:
    raise SystemExit("baseline disk has no file source")
nvram.text = nvram_path
source_node.set("file", disk_path)
tree.write(target, encoding="unicode", xml_declaration=True)
PY
chmod 0600 "$work_dir/domain.xml"

virsh_system define "$work_dir/domain.xml" >/dev/null
defined=1
verification_uuid=$(virsh_system domuuid "$verification_domain")
test "$verification_uuid" != "$expected_uuid" || {
  printf 'verify restore: verification domain reused the protected UUID\n' >&2
  exit 1
}
check_protected_guard
virsh_system start "$verification_domain" >/dev/null
check_protected_guard

qga_exec() {
  local executable=$1
  shift
  local arguments_json payload response pid status encoded exit_code
  arguments_json=$(printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]')
  payload=$(jq -nc --arg path "$executable" --argjson arg "$arguments_json" \
    '{execute:"guest-exec",arguments:{path:$path,arg:$arg,"capture-output":true}}')
  response=
  for _attempt in $(seq 1 90); do
    check_protected_guard
    if response=$(virsh_system qemu-agent-command "$verification_domain" "$payload" 2>/dev/null); then
      break
    fi
    sleep 1
  done
  test -n "$response" || {
    printf 'verify restore: guest agent did not become ready before timeout\n' >&2
    return 1
  }
  pid=$(jq -er '.return.pid | numbers' <<<"$response")
  for _attempt in $(seq 1 90); do
    check_protected_guard
    if ! status=$(virsh_system qemu-agent-command "$verification_domain" \
      "$(jq -nc --argjson pid "$pid" '{execute:"guest-exec-status",arguments:{pid:$pid}}')" 2>/dev/null); then
      sleep 1
      continue
    fi
    if jq -e '.return.exited == true' <<<"$status" >/dev/null; then
      exit_code=$(jq -er '.return.exitcode | numbers' <<<"$status")
      test "$exit_code" = 0 || return "$exit_code"
      encoded=$(jq -r '.return["out-data"] // ""' <<<"$status")
      printf '%s' "$encoded" | base64 --decode
      return 0
    fi
    sleep 1
  done
  printf 'verify restore: guest-agent command timed out\n' >&2
  return 1
}

actual_system=$(qga_exec /run/current-system/sw/bin/readlink -f /run/current-system)
actual_system=${actual_system%$'\n'}
test "$actual_system" = "$expected_system" || {
  printf 'verify restore: restored generation mismatch\n' >&2
  exit 1
}
greetd_state=$(qga_exec /run/current-system/sw/bin/systemctl is-active greetd.service)
greetd_state=${greetd_state%$'\n'}
test "$greetd_state" = active || {
  printf 'verify restore: restored guest did not reach active greetd/ReGreet lifecycle\n' >&2
  exit 1
}
regreet_state=$(qga_exec /run/current-system/sw/bin/pgrep -x regreet)
test -n "${regreet_state%$'\n'}" || {
  printf 'verify restore: restored guest has no live ReGreet process\n' >&2
  exit 1
}
cage_state=$(qga_exec /run/current-system/sw/bin/pgrep -x cage)
test -n "${cage_state%$'\n'}" || {
  printf 'verify restore: restored guest has no live ReGreet compositor process\n' >&2
  exit 1
}
check_protected_guard

virsh_system qemu-agent-command "$verification_domain" \
  '{"execute":"guest-shutdown","arguments":{"mode":"powerdown"}}' >/dev/null
state=
for _attempt in $(seq 1 60); do
  check_protected_guard
  state=$(virsh_system domstate "$verification_domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  test "$state" = 'shut off' && break
  sleep 1
done
test "$state" = 'shut off' || {
  printf 'verify restore: temporary guest did not shut down cleanly\n' >&2
  exit 1
}

check_protected_guard
stop_protected_guard
if test -e "$protected_guard_failure" ||
  grep -Eiq 'started|resumed' "$protected_event_log" 2>/dev/null ||
  ! assert_protected_identity_offline; then
  printf 'verify restore: protected-domain lifecycle evidence failed before report\n' >&2
  exit 1
fi
cleanup
defined=0
trap - EXIT HUP INT TERM
assert_protected_identity_offline || {
  printf 'verify restore: protected domain was not safely offline at final report time\n' >&2
  exit 1
}
jq -n \
  --arg domain "$domain" \
  --arg verificationDomain "$verification_domain" \
  --arg verificationUuid "$verification_uuid" \
  --arg expectedSystem "$expected_system" \
  --arg actualSystem "$actual_system" \
  '{
    schemaVersion: 1,
    domain: $domain,
    verificationDomain: $verificationDomain,
    verificationUuid: $verificationUuid,
    expectedSystem: $expectedSystem,
    actualSystem: $actualSystem,
    greetd: "active",
    regreet: "running",
    greeterCompositor: "cage-running",
    temporaryDomainRemoved: true,
    protectedDomainStarted: false
  }' >"$report"
chmod 0600 "$report"
printf '%s\n' "$report"
