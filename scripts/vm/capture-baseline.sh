#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  printf 'usage: %s --domain Sleepy --run-dir /absolute/new-directory --expected-system /nix/store/...\n' "${0##*/}" >&2
  exit 2
}

domain=
run_dir=
expected_system=
while test "$#" -gt 0; do
  case "$1" in
    --domain)
      test "$#" -ge 2 || usage
      domain=$2
      shift 2
      ;;
    --run-dir)
      test "$#" -ge 2 || usage
      run_dir=$2
      shift 2
      ;;
    --expected-system)
      test "$#" -ge 2 || usage
      expected_system=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

virsh_system() {
  command virsh --connect qemu:///system "$@"
}

test "$domain" = Sleepy || {
  printf 'capture baseline: refusing domain other than exact target Sleepy\n' >&2
  exit 2
}
case "$expected_system" in
  /nix/store/*-nixos-system-sleepy*) ;;
  *)
    printf 'capture baseline: expected system must be an absolute Sleepy NixOS store path\n' >&2
    exit 2
    ;;
esac
case "$run_dir" in
  /*) ;;
  *)
    printf 'capture baseline: run directory must be absolute\n' >&2
    exit 2
    ;;
esac

for command_name in awk cp grep install jq mkdir python3 qemu-img realpath sed sha256sum stat tr virsh; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'capture baseline: required command not found: %s\n' "$command_name" >&2
    exit 127
  }
done

run_parent=$(dirname -- "$run_dir")
run_name=$(basename -- "$run_dir")
case "$run_name" in
  '' | '.' | '..' | *[!A-Za-z0-9._-]*)
    printf 'capture baseline: unsafe run-directory basename\n' >&2
    exit 2
    ;;
esac
test -d "$run_parent" && test ! -L "$run_parent" || {
  printf 'capture baseline: run-directory parent must be an existing non-symlink directory\n' >&2
  exit 1
}
run_parent=$(realpath -e -- "$run_parent")
run_dir="$run_parent/$run_name"
if test -e "$run_dir" || test -L "$run_dir"; then
  printf 'capture baseline: refusing to replace run directory: %s\n' "$run_dir" >&2
  exit 1
fi

domain_uuid=$(virsh_system domuuid "$domain")
case "$domain_uuid" in
  ????????-????-????-????-????????????) ;;
  *)
    printf 'capture baseline: libvirt returned an invalid UUID for %s\n' "$domain" >&2
    exit 1
    ;;
esac
domain_state=$(virsh_system domstate "$domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
test "$domain_state" = 'shut off' || {
  printf 'capture baseline: %s must be shut off, got: %s\n' "$domain" "$domain_state" >&2
  exit 1
}

mkdir -m 0700 -- "$run_dir"
capture_complete=0
cleanup_incomplete() {
  local exit_status=$?
  if test "$capture_complete" != 1; then
    rm -f -- \
      "$run_dir/domain.xml.tmp" \
      "$run_dir/xml-metadata.tsv" \
      "$run_dir/domain.xml" \
      "$run_dir/nvram.fd" \
      "$run_dir/disk.qcow2" \
      "$run_dir/backing-chain.json" \
      "$run_dir/copy-info.json" \
      "$run_dir/disk-check.json" \
      "$run_dir/manifest.json" \
      "$run_dir/checksums.sha256" \
      "$run_dir/bundle.incomplete" \
      "$run_dir/bundle.complete"
    rmdir -- "$run_dir" 2>/dev/null || {
      printf 'capture baseline: incomplete private directory requires manual inspection: %s\n' "$run_dir" >&2
    }
  fi
  return "$exit_status"
}
trap cleanup_incomplete EXIT
status_file="$run_dir/bundle.incomplete"
printf 'capture in progress; do not use as a rollback source\n' >"$status_file"
chmod 0600 "$status_file"

xml_tmp="$run_dir/domain.xml.tmp"
virsh_system dumpxml --inactive "$domain" >"$xml_tmp"
chmod 0600 "$xml_tmp"
if ! python3 - "$xml_tmp" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

credential_name = re.compile(
    r"(?:pass(?:word|wd)?|token|secret|credential|api[-_]?key|access[-_]?key|private[-_]?key)",
    re.IGNORECASE,
)
credential_value = re.compile(
    r"(?:bearer[ ]+[A-Za-z0-9._~+/-]+|BEGIN [A-Z ]*PRIVATE KEY|(?<![A-Za-z0-9])(?:pass(?:word|wd)?|token|secret|credential|api[-_ ]?key|access[-_ ]?key|private[-_ ]?key)(?![A-Za-z0-9]))",
    re.IGNORECASE,
)

root = ET.parse(sys.argv[1]).getroot()
for element in root.iter():
    local_tag = element.tag.rsplit("}", 1)[-1]
    if credential_name.search(local_tag) or local_tag in {"auth", "secret"}:
        raise SystemExit(1)
    for attribute in element.attrib:
        local_attribute = attribute.rsplit("}", 1)[-1]
        if credential_name.search(local_attribute):
            raise SystemExit(1)
    for value in [element.text, element.tail, *element.attrib.values()]:
        if value and credential_value.search(value):
            raise SystemExit(1)

# Custom metadata and QEMU command/environment extensions are opaque to this
# tool. Refuse them instead of guessing whether their contents are safe.
metadata = root.find("metadata")
if metadata is not None and (list(metadata) or (metadata.text or "").strip()):
    raise SystemExit(1)
for element in root.iter():
    namespace = element.tag[1:].split("}", 1)[0] if element.tag.startswith("{") else ""
    local_tag = element.tag.rsplit("}", 1)[-1]
    if "libvirt.org/schemas/domain/qemu" in namespace or local_tag in {"commandline", "env"}:
        raise SystemExit(1)
PY
then
  printf 'capture baseline: inactive XML contains credential-bearing fields; refusing to persist it\n' >&2
  exit 1
fi

xml_metadata="$run_dir/xml-metadata.tsv"
python3 - "$xml_tmp" >"$xml_metadata" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
name = root.findtext("name")
uuid = root.findtext("uuid")
nvram = root.findtext("./os/nvram")
disks = []
for disk in root.findall("./devices/disk"):
    if disk.get("device") != "disk" or disk.get("type") != "file":
        continue
    source = disk.find("source")
    target = disk.find("target")
    driver = disk.find("driver")
    if source is None or target is None or driver is None:
        continue
    disks.append((source.get("file"), target.get("dev"), driver.get("type")))
if name != "Sleepy" or not uuid or not nvram or len(disks) != 1:
    raise SystemExit("expected exact Sleepy XML with one file-backed disk and one NVRAM path")
values = (name, uuid, nvram, *disks[0])
if any(value is None or "\n" in value or "\t" in value for value in values):
    raise SystemExit("invalid XML path metadata")
print("\t".join(values))
PY
chmod 0600 "$xml_metadata"
IFS=$'\t' read -r xml_name xml_uuid nvram_source disk_source disk_target disk_format <"$xml_metadata"
test "$xml_name" = "$domain" && test "$xml_uuid" = "$domain_uuid" || {
  printf 'capture baseline: libvirt identity changed during capture\n' >&2
  exit 1
}
test "$disk_format" = qcow2 || {
  printf 'capture baseline: expected qcow2 system disk, got %s\n' "$disk_format" >&2
  exit 1
}

block_source=$(virsh_system domblklist --inactive --details "$domain" | awk -v target="$disk_target" '$2 == "disk" && $3 == target { print $4 }')
test "$block_source" = "$disk_source" || {
  printf 'capture baseline: inactive XML and block inventory disagree\n' >&2
  exit 1
}

for source_path in "$disk_source" "$nvram_source"; do
  case "$source_path" in
    /*) ;;
    *)
      printf 'capture baseline: source path is not absolute: %s\n' "$source_path" >&2
      exit 1
      ;;
  esac
  test -f "$source_path" && test ! -L "$source_path" || {
    printf 'capture baseline: source must be a regular non-symlink file: %s\n' "$source_path" >&2
    exit 1
  }
done
disk_source=$(realpath -e -- "$disk_source")
nvram_source=$(realpath -e -- "$nvram_source")
disk_mode=$(stat -c %a "$disk_source")
disk_uid=$(stat -c %u "$disk_source")
disk_gid=$(stat -c %g "$disk_source")
disk_size=$(stat -c %s "$disk_source")
nvram_mode=$(stat -c %a "$nvram_source")
nvram_uid=$(stat -c %u "$nvram_source")
nvram_gid=$(stat -c %g "$nvram_source")
nvram_size=$(stat -c %s "$nvram_source")

qemu-img info --backing-chain --output=json "$disk_source" >"$run_dir/backing-chain.json"
jq -e --arg disk "$disk_source" '
  type == "array" and length >= 1 and
  .[0].filename == $disk and .[0].format == "qcow2" and
  all(.[]; (.filename | type == "string") and (.format | type == "string"))
' "$run_dir/backing-chain.json" >/dev/null

qemu-img convert -p -O qcow2 -- "$disk_source" "$run_dir/disk.qcow2"
qemu-img info --backing-chain --output=json "$run_dir/disk.qcow2" >"$run_dir/copy-info.json"
jq -e --arg disk "$run_dir/disk.qcow2" '
  type == "array" and length == 1 and
  .[0].filename == $disk and .[0].format == "qcow2" and
  ((.[0]["backing-filename"] // null) == null) and
  ((.[0]["full-backing-filename"] // null) == null)
' "$run_dir/copy-info.json" >/dev/null
qemu-img check --output=json "$run_dir/disk.qcow2" >"$run_dir/disk-check.json"
jq -e '
  (.corruptions // 0) == 0 and
  (.leaks // 0) == 0 and
  (."check-errors" // 0) == 0
' "$run_dir/disk-check.json" >/dev/null
cp --reflink=auto --sparse=always -- "$nvram_source" "$run_dir/nvram.fd"
install -m 0600 -- "$xml_tmp" "$run_dir/domain.xml"

jq -n \
  --arg domain "$domain" \
  --arg uuid "$domain_uuid" \
  --arg expectedSystem "$expected_system" \
  --arg diskSource "$disk_source" \
  --arg diskTarget "$disk_target" \
  --arg diskFormat "$disk_format" \
  --argjson diskMode "$disk_mode" \
  --argjson diskUid "$disk_uid" \
  --argjson diskGid "$disk_gid" \
  --argjson diskSize "$disk_size" \
  --arg nvramSource "$nvram_source" \
  --argjson nvramMode "$nvram_mode" \
  --argjson nvramUid "$nvram_uid" \
  --argjson nvramGid "$nvram_gid" \
  --argjson nvramSize "$nvram_size" \
  '{
    schemaVersion: 1,
    kind: "sleepy-offline-rollback-bundle",
    completed: true,
    domain: {name: $domain, uuid: $uuid, capturedState: "shut off"},
    expectedSystem: $expectedSystem,
    disk: {
      originalSource: $diskSource,
      originalTarget: $diskTarget,
      originalFormat: $diskFormat,
      originalMode: $diskMode,
      originalUid: $diskUid,
      originalGid: $diskGid,
      originalSize: $diskSize,
      copyFormat: "qcow2",
      copyIsFlattened: true
    },
    nvram: {
      originalSource: $nvramSource,
      originalMode: $nvramMode,
      originalUid: $nvramUid,
      originalGid: $nvramGid,
      originalSize: $nvramSize
    },
    artifacts: {
      xml: "domain.xml",
      nvram: "nvram.fd",
      disk: "disk.qcow2",
      backingChain: "backing-chain.json",
      copyInfo: "copy-info.json",
      diskCheck: "disk-check.json"
    }
  }' >"$run_dir/manifest.json"

chmod 0600 "$run_dir"/*
(
  cd "$run_dir"
  sha256sum domain.xml nvram.fd disk.qcow2 backing-chain.json copy-info.json disk-check.json manifest.json >checksums.sha256
)
chmod 0600 "$run_dir/checksums.sha256"
rm -f -- "$xml_tmp" "$xml_metadata" "$status_file"
printf 'verified offline rollback bundle; checksums must pass before use\n' >"$run_dir/bundle.complete"
chmod 0600 "$run_dir/bundle.complete"
test "$(virsh_system domuuid "$domain")" = "$domain_uuid"
test "$(virsh_system domstate "$domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" = 'shut off'
capture_complete=1
trap - EXIT

printf '%s\n' "$run_dir"
