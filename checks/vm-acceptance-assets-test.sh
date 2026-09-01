#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

for command_name in base64 cmp jq mktemp sha256sum stat; do
  command -v "$command_name" >/dev/null || {
    printf 'VM acceptance assets: missing test dependency %s\n' "$command_name" >&2
    exit 127
  }
done

grep -F 'hyprlandPackage = nixosConfig.programs.hyprland.package;' \
  "$repo_root/checks/hyprland-production-vm.nix" >/dev/null || {
  printf 'VM acceptance assets: production test must use the non-null NixOS Hyprland package\n' >&2
  exit 1
}
for rollback_guard in \
  "test \"\$live_disk\" = \"\$original_disk\"" \
  "test \"\$live_nvram\" = \"\$original_nvram\""; do
  grep -F "$rollback_guard" "$repo_root/docs/runbooks/sleepy-vm-hyprland.md" >/dev/null || {
    printf 'VM acceptance assets: rollback runbook must verify live disk and NVRAM sources\n' >&2
    exit 1
  }
done

for required in \
  checks/hyprland-production-vm.nix \
  scripts/vm/capture-baseline.sh \
  scripts/vm/verify-restore.sh \
  scripts/vm/collect-evidence.sh \
  docs/runbooks/sleepy-vm-hyprland.md \
  docs/acceptance/hyprland-sleepy-desktop.md; do
  if ! test -f "$repo_root/$required"; then
    printf 'VM acceptance assets: missing %s\n' "$required" >&2
    exit 1
  fi
done

fixture=$(mktemp -d /tmp/sleepy-vm-acceptance.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
fake_bin="$fixture/bin"
mkdir -m 0700 "$fake_bin" "$fixture/source"
disk="$fixture/source/sleepy.qcow2"
nvram="$fixture/source/sleepy_VARS.fd"
printf 'sleepy-disk-baseline\n' >"$disk"
printf 'sleepy-nvram-baseline\n' >"$nvram"
chmod 0600 "$disk" "$nvram"
export FAKE_VM_LOG="$fixture/virsh.log"
export FAKE_VM_STATE_DIR="$fixture/state"
export FAKE_DISK="$disk"
export FAKE_NVRAM="$nvram"
mkdir -m 0700 "$FAKE_VM_STATE_DIR"
: >"$FAKE_VM_LOG"

cat >"$fake_bin/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test "${1:-}" = --connect
test "${2:-}" = qemu:///system
shift 2
printf '%s\t' "$@" >>"$FAKE_VM_LOG"
printf '\n' >>"$FAKE_VM_LOG"

command_name=${1:-}
shift || true
case "$command_name" in
  domuuid)
    domain=${1:-}
    if test "$domain" = Sleepy; then
      printf '%s\n' '11111111-2222-4333-8444-555555555555'
    elif test -e "$FAKE_VM_STATE_DIR/defined" && test "$domain" = Sleepy-restore-verification; then
      printf '%s\n' 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
    else
      exit 1
    fi
    ;;
  domstate)
    domain=${1:-}
    if test "$domain" = Sleepy; then
      printf '%s\n' "${FAKE_DOMAIN_STATE:-shut off}"
    elif test "$domain" = Sleepy-restore-verification && test -e "$FAKE_VM_STATE_DIR/running"; then
      printf '%s\n' running
    elif test "$domain" = Sleepy-restore-verification && test -e "$FAKE_VM_STATE_DIR/defined"; then
      printf '%s\n' 'shut off'
    else
      exit 1
    fi
    ;;
  dumpxml)
    domain=${*: -1}
    if test "$domain" = Sleepy; then
      secret_attribute=
      if test "${FAKE_XML_SECRET:-0}" = 1; then
        secret_attribute=" passwd='do-not-persist'"
      fi
      cat <<XML
<domain type='kvm'>
  <name>Sleepy</name>
  <uuid>11111111-2222-4333-8444-555555555555</uuid>
  <os><nvram>$FAKE_NVRAM</nvram></os>
  <devices>
    <disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source file='$FAKE_DISK'/><target dev='vda' bus='virtio'/></disk>
    <graphics type='spice' autoport='yes'$secret_attribute/>
  </devices>
</domain>
XML
    elif test "$domain" = Sleepy-restore-verification && test -e "$FAKE_VM_STATE_DIR/defined.xml"; then
      cat "$FAKE_VM_STATE_DIR/defined.xml"
    else
      exit 1
    fi
    ;;
  domblklist)
    cat <<ROWS
Type       Device     Target     Source
------------------------------------------------
file       disk       vda        $FAKE_DISK
ROWS
    ;;
  dominfo)
    domain=${1:-}
    if test "$domain" = Sleepy-restore-verification && test -e "$FAKE_VM_STATE_DIR/defined"; then
      printf 'Name: Sleepy-restore-verification\n'
    else
      exit 1
    fi
    ;;
  define)
    cp "$1" "$FAKE_VM_STATE_DIR/defined.xml"
    touch "$FAKE_VM_STATE_DIR/defined"
    printf 'Domain Sleepy-restore-verification defined\n'
    ;;
  start)
    test "$1" = Sleepy-restore-verification
    touch "$FAKE_VM_STATE_DIR/running"
    ;;
  qemu-agent-command)
    domain=$1
    payload=$2
    test "$domain" = Sleepy-restore-verification || test "$domain" = Sleepy
    if test "${FAKE_QGA_DELAY_CALLS:-0}" -gt 0; then
      qga_calls=0
      if test -f "$FAKE_VM_STATE_DIR/qga-calls"; then
        qga_calls=$(cat "$FAKE_VM_STATE_DIR/qga-calls")
      fi
      if test "$qga_calls" -lt "$FAKE_QGA_DELAY_CALLS"; then
        printf '%s\n' "$((qga_calls + 1))" >"$FAKE_VM_STATE_DIR/qga-calls"
        exit 1
      fi
    fi
    case "$payload" in
      *guest-exec-status*)
        request=$(cat "$FAKE_VM_STATE_DIR/qga-request")
        if test "$request" = current-system; then
          encoded=$(printf '%s\n' '/nix/store/accepted-nixos-system-sleepy' | base64 -w0)
        else
          encoded=$(printf '%s\n' active | base64 -w0)
        fi
        printf '{"return":{"exited":true,"exitcode":0,"out-data":"%s"}}\n' "$encoded"
        ;;
      *guest-shutdown*)
        rm -f -- "$FAKE_VM_STATE_DIR/running"
        printf '{"return":{}}\n'
        ;;
      *readlink*)
        printf '%s\n' current-system >"$FAKE_VM_STATE_DIR/qga-request"
        printf '{"return":{"pid":41}}\n'
        ;;
      *systemctl*)
        printf '%s\n' greetd >"$FAKE_VM_STATE_DIR/qga-request"
        printf '{"return":{"pid":42}}\n'
        ;;
      *) exit 2 ;;
    esac
    ;;
  undefine)
    test "$1" = Sleepy-restore-verification
    test "${FAKE_UNDEFINE_FAIL:-0}" != 1 || exit 1
    rm -f -- "$FAKE_VM_STATE_DIR/defined" "$FAKE_VM_STATE_DIR/defined.xml" "$FAKE_VM_STATE_DIR/running"
    ;;
  *)
    printf 'unexpected fake virsh command: %s\n' "$command_name" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$fake_bin/virsh"

cat >"$fake_bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  info)
    disk=${*: -1}
    if test "${FAKE_COPY_HAS_BACKING:-0}" = 1 && test "$disk" != "$FAKE_DISK"; then
      jq -n --arg filename "$disk" --arg backing "$FAKE_DISK" '[{"filename":$filename,"format":"qcow2","backing-filename":$backing,"virtual-size":67108864},{"filename":$backing,"format":"qcow2","virtual-size":67108864}]'
    else
      jq -n --arg filename "$disk" '[{"filename":$filename,"format":"qcow2","virtual-size":67108864}]'
    fi
    ;;
  convert)
    source_path=${*: -2:1}
    destination_path=${*: -1}
    cp --sparse=always -- "$source_path" "$destination_path"
    ;;
  check)
    jq -n '{"image-end-offset":4096,"corruptions":0,"leaks":0,"check-errors":0}'
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$fake_bin/qemu-img"

assert_rejected() {
  local label=$1
  shift
  if "$@" >"$fixture/$label.stdout" 2>"$fixture/$label.stderr"; then
    printf 'VM acceptance assets: accepted unsafe scenario %s\n' "$label" >&2
    exit 1
  fi
}

bundle="$fixture/baseline"
PATH="$fake_bin:$PATH" "$repo_root/scripts/vm/capture-baseline.sh" \
  --domain Sleepy \
  --run-dir "$bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy

test "$(stat -c %a "$bundle")" = 700
for artifact in domain.xml nvram.fd disk.qcow2 backing-chain.json copy-info.json disk-check.json manifest.json checksums.sha256 bundle.complete; do
  test -f "$bundle/$artifact"
  test "$(stat -c %a "$bundle/$artifact")" = 600
done
(cd "$bundle" && sha256sum --check checksums.sha256)
jq -e '
  .schemaVersion == 1 and
  .domain.name == "Sleepy" and
  .domain.uuid == "11111111-2222-4333-8444-555555555555" and
  .expectedSystem == "/nix/store/accepted-nixos-system-sleepy" and
  .disk.originalTarget == "vda" and
  .disk.originalFormat == "qcow2" and
  .disk.originalMode == 600 and
  (.disk.originalUid | type == "number") and
  (.disk.originalGid | type == "number") and
  .nvram.originalMode == 600 and
  .artifacts.xml == "domain.xml" and
  .artifacts.nvram == "nvram.fd" and
  .artifacts.disk == "disk.qcow2"
' "$bundle/manifest.json" >/dev/null
cmp "$disk" "$bundle/disk.qcow2"
cmp "$nvram" "$bundle/nvram.fd"

existing_hash=$(sha256sum "$bundle/manifest.json")
assert_rejected existing-run-dir env PATH="$fake_bin:$PATH" \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test "$(sha256sum "$bundle/manifest.json")" = "$existing_hash"

active_bundle="$fixture/active-baseline"
assert_rejected active-domain env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$active_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$active_bundle"

secret_bundle="$fixture/secret-baseline"
assert_rejected credential-xml env PATH="$fake_bin:$PATH" FAKE_XML_SECRET=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$secret_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$secret_bundle"

backed_copy_bundle="$fixture/backed-copy-baseline"
assert_rejected non-flattened-copy env PATH="$fake_bin:$PATH" FAKE_COPY_HAS_BACKING=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$backed_copy_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$backed_copy_bundle"

assert_rejected ambiguous-domain env PATH="$fake_bin:$PATH" \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain sleepy --run-dir "$fixture/wrong-domain" \
  --expected-system /nix/store/accepted-nixos-system-sleepy

PATH="$fake_bin:$PATH" FAKE_QGA_DELAY_CALLS=2 "$repo_root/scripts/vm/verify-restore.sh" \
  --bundle "$bundle" \
  --domain Sleepy \
  --verification-domain Sleepy-restore-verification
test ! -e "$FAKE_VM_STATE_DIR/defined"
grep -F $'define\t' "$FAKE_VM_LOG" >/dev/null
grep -F $'start\tSleepy-restore-verification\t' "$FAKE_VM_LOG" >/dev/null
grep -F $'undefine\tSleepy-restore-verification\t--nvram\t' "$FAKE_VM_LOG" >/dev/null
if grep -E $'^(start|undefine|destroy)\tSleepy\t' "$FAKE_VM_LOG" >/dev/null; then
  printf 'VM acceptance assets: restore drill mutated the protected domain\n' >&2
  exit 1
fi

tampered="$fixture/tampered"
cp -a -- "$bundle" "$tampered"
chmod 0700 "$tampered"
printf 'tamper\n' >>"$tampered/disk.qcow2"
: >"$FAKE_VM_LOG"
assert_rejected tampered-bundle env PATH="$fake_bin:$PATH" \
  "$repo_root/scripts/vm/verify-restore.sh" --bundle "$tampered" --domain Sleepy \
  --verification-domain Sleepy-restore-verification
test ! -s "$FAKE_VM_LOG"

cleanup_bundle="$fixture/cleanup-failure"
cp -a -- "$bundle" "$cleanup_bundle"
rm -f -- "$cleanup_bundle/restore-verification.json"
: >"$FAKE_VM_LOG"
assert_rejected cleanup-failure env PATH="$fake_bin:$PATH" FAKE_UNDEFINE_FAIL=1 \
  "$repo_root/scripts/vm/verify-restore.sh" --bundle "$cleanup_bundle" --domain Sleepy \
  --verification-domain Sleepy-restore-verification
grep -F 'FAILED to remove the identity-checked temporary domain' \
  "$fixture/cleanup-failure.stderr" >/dev/null
test -e "$FAKE_VM_STATE_DIR/defined"
rm -f -- "$FAKE_VM_STATE_DIR/defined" "$FAKE_VM_STATE_DIR/defined.xml" \
  "$FAKE_VM_STATE_DIR/running" "$FAKE_VM_STATE_DIR/qga-calls" "$FAKE_VM_STATE_DIR/qga-request"

redacted="$fixture/redacted-desktop.png"
printf '\211PNG\r\n\032\nredacted-framebuffer\n' >"$redacted"
chmod 0600 "$redacted"
runtime="$fixture/redacted-runtime.json"
jq -n '{
  schemaVersion: 1,
  redacted: true,
  candidate: {
    system: "/nix/store/candidate-nixos-system-sleepy",
    rootCommit: "1111111111111111111111111111111111111111",
    components: {
      sleepySdk: "2222222222222222222222222222222222222222",
      sleepySession: "3333333333333333333333333333333333333333",
      sleepyArtwork: "4444444444444444444444444444444444444444",
      sleepyDesktop: "5555555555555555555555555555555555555555"
    }
  },
  services: {
    sleepySession: "active",
    sleepyShell: "active",
    sleepyLocker: "active",
    failedUserUnits: 0,
    failedSystemUnits: 0
  },
  compositor: {hyprlandSocket: true, niriProcess: false},
  snapshot: {schemaVersion: 3, type: "fullSnapshot", generation: 1},
  functional: {
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
  }
}' >"$runtime"
chmod 0600 "$runtime"
evidence="$fixture/evidence"
PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" \
  --domain Sleepy \
  --run-dir "$evidence" \
  --label unlocked-desktop \
  --redacted-framebuffer "$redacted" \
  --redacted-runtime "$runtime" \
  --confirm-redacted \
  --reviewer local-owner \
  --delete-after 2099-10-01
test "$(stat -c %a "$evidence")" = 700
for artifact in runtime.json unlocked-desktop.png evidence.json checksums.sha256 evidence.complete; do
  test -f "$evidence/$artifact"
  test "$(stat -c %a "$evidence/$artifact")" = 600
done
(cd "$evidence" && sha256sum --check checksums.sha256)
jq -e '
  .schemaVersion == 1 and
  .domain.name == "Sleepy" and
  .reviewer == "local-owner" and
  .deleteAfter == "2099-10-01" and
  .redaction.confirmed == true and
  .rawArtifactsRetained == false
' "$evidence/evidence.json" >/dev/null
cmp "$redacted" "$evidence/unlocked-desktop.png"

assert_rejected missing-redaction-confirmation env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/unconfirmed-evidence" --label desktop \
  --redacted-framebuffer "$redacted" --redacted-runtime "$runtime" \
  --reviewer local-owner --delete-after 2099-10-01

not_png="$fixture/not-redacted-image.png"
printf 'not a PNG\n' >"$not_png"
chmod 0600 "$not_png"
assert_rejected invalid-png env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/invalid-png-evidence" --label desktop \
  --redacted-framebuffer "$not_png" --redacted-runtime "$runtime" --confirm-redacted \
  --reviewer local-owner --delete-after 2099-10-01

assert_rejected unsafe-label env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/unsafe-evidence" --label ../escape \
  --redacted-framebuffer "$redacted" --redacted-runtime "$runtime" \
  --confirm-redacted \
  --reviewer local-owner --delete-after 2099-10-01

assert_rejected evidence-offline env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE='shut off' \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/offline-evidence" --label desktop \
  --redacted-framebuffer "$redacted" --redacted-runtime "$runtime" \
  --confirm-redacted \
  --reviewer local-owner --delete-after 2099-10-01

printf 'VM acceptance assets: ok\n'
