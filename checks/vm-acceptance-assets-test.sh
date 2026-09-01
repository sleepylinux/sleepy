#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

for command_name in base64 cmp install jq mktemp pngcheck python3 sha256sum stat; do
  command -v "$command_name" >/dev/null || {
    printf 'VM acceptance assets: missing test dependency %s\n' "$command_name" >&2
    exit 127
  }
done

validate_production_contract() {
  local production_check=$1
  for required_literal in \
    'sdkSource}/schemas/desktop-event-v3.schema.json' \
    'Draft202012Validator(schema, format_checker=FormatChecker()).validate(document)' \
    "grep -F 'Loaded TOML file:' /var/log/regreet/log" \
    'enableOCR = true;' \
    'machine.wait_for_text("Welcome back!", timeout=timedelta(seconds=30))' \
    'regreetTestState = pkgs.writeText "regreet-test-state.toml"' \
    'selectedSessionName = "Hyprland (uwsm-managed)";' \
    'lazy = "${selectedSessionName}"' \
    'assert session_name == "${selectedSessionName}"' \
    'machine.wait_for_text(re.escape("${selectedSessionName}"), timeout=timedelta(seconds=30))' \
    'machine.send_key("ret")' \
    'regreet_ready = "pgrep -f' \
    '${pkgs.cage}/bin/cage -s -d -- ${pkgs.regreet}/bin/regreet' \
    'hyprland_ready = "pgrep -u lazy -f -x' \
    '${hyprlandPackage}/bin/Hyprland --watchdog-fd [0-9]+' \
    'niri_absent = "! pgrep -u lazy -f -x' \
    '${pkgs.niri}/bin/niri([[:space:]].*)?' \
    'useDefaultRules = false;' \
    'rules = lib.mkForce {' \
    'modulePath = "${config.security.pam.package}/lib/security/pam_permit.so";' \
    'modulePath = "${config.systemd.package}/lib/security/pam_systemd.so";' \
    "grep -F 'Creating session for username: lazy' /var/log/regreet/log" \
    'systemctl --user is-active wayland-wm@hyprland.desktop.service", timeout=timedelta(seconds=30))' \
    'DAEMON_RESTART_RECOVERY_GATE' \
    'post_daemon = read_snapshot("/tmp/desktop-post-daemon.json")' \
    'SHELL_RESTART_RECOVERY_GATE' \
    'post_shell = read_snapshot("/tmp/desktop-post-shell.json")' \
    'wait_for_shell_stream(shell_pid)' \
    'legacy_manifest = ' \
    'assert machine.succeed(legacy_manifest) == prior_hashes'; do
    grep -F "$required_literal" "$production_check" >/dev/null || return 1
  done
  for forbidden_literal in \
    'loginctl enable-linger' \
    'sleepy-test-weston.service' \
    'sleepy-test-hyprland.service' \
    'production-vm-sentinel'; do
    ! grep -F "$forbidden_literal" "$production_check" >/dev/null || return 1
  done
}

validate_production_contract "$repo_root/checks/hyprland-production-vm.nix" || {
  printf 'VM acceptance assets: production VM contract is incomplete or bypasses ReGreet/UWSM\n' >&2
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

validate_rollback_contract() {
  python3 - "$1" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
conversion = text.index("sudo qemu-img convert -p -O qcow2")
first_move = text.index('sudo mv -- "$original_disk" "$failed_disk"')
initial_identity = [
    'original_disk_identity=$(stat -Lc \'%d:%i\' -- "$original_disk")',
    'original_nvram_identity=$(stat -Lc \'%d:%i\' -- "$original_nvram")',
]
final_guards = [
    'final_state=$(virsh --connect qemu:///system domstate Sleepy | xargs)',
    'final_uuid=$(virsh --connect qemu:///system domuuid Sleepy)',
    'final_disk=$(virsh --connect qemu:///system domblklist --inactive --details Sleepy |',
    'final_nvram=$(virsh --connect qemu:///system dumpxml Sleepy --inactive |',
    'test "$final_state" = "shut off"',
    'test "$final_disk" = "$original_disk"',
    'test "$final_nvram" = "$original_nvram"',
    'test "$(stat -Lc \'%d:%i\' -- "$original_disk")" = "$original_disk_identity"',
    'test "$(stat -Lc \'%d:%i\' -- "$original_nvram")" = "$original_nvram_identity"',
]
for literal in initial_identity:
    if text.index(literal) > conversion:
        raise SystemExit(f"rollback identity was not recorded before conversion: {literal}")
for literal in final_guards:
    position = text.index(literal)
    if not conversion < position < first_move:
        raise SystemExit(f"final rollback guard is not immediately pre-move: {literal}")
PY
}

validate_rollback_contract "$repo_root/docs/runbooks/sleepy-vm-hyprland.md"

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

fixture=$(mktemp -d "${TMPDIR:-/tmp}/sleepy-vm-acceptance.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
fake_bin="$fixture/bin"
mkdir -m 0700 "$fake_bin" "$fixture/source"
test -w "$fixture/source" || {
  printf 'VM acceptance assets: fixture source directory is not writable: ' >&2
  stat -c '%A %a %u:%g %n' "$fixture" "$fixture/source" >&2
  exit 1
}

mutated_production="$fixture/source/hyprland-production-vm.nix"
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/machine.send_key("ret")/pass # neutralized ReGreet submit/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized ReGreet gate mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/regreet_ready = .*/regreet_ready = "true"/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized ReGreet readiness mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/machine.wait_for_text("Welcome back!", timeout=timedelta(seconds=30))/pass # neutralized visible ReGreet readiness/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized visible ReGreet readiness mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/enableOCR = true;/enableOCR = false;/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: disabled ReGreet OCR dependency mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/selectedSessionName = "Hyprland (uwsm-managed)"/selectedSessionName = "Hyprland"/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: direct-session ReGreet state mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/machine.wait_for_text(re.escape("${selectedSessionName}"), timeout=timedelta(seconds=30))/pass # neutralized visible UWSM selection/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized visible UWSM selection mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/hyprland_ready = .*/hyprland_ready = "true"/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized Hyprland readiness mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/wayland-wm@hyprland.desktop.service/wayland-wm@Hyprland.desktop.target/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: case-wrong UWSM target mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/niri_absent = .*/niri_absent = "true"/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: neutralized wrapped Niri exclusion mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i '/post_daemon = read_snapshot("\/tmp\/desktop-post-daemon.json")/d; /post_shell = read_snapshot("\/tmp\/desktop-post-shell.json")/d' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: removed restart snapshot mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's#${config.systemd.package}/lib/security/pam_systemd.so#${config.security.pam.package}/lib/security/pam_systemd.so#' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: PAM systemd provider mutation passed\n' >&2
  exit 1
fi
install -m 0600 -- "$repo_root/checks/hyprland-production-vm.nix" "$mutated_production"
sed -i 's/rules = lib.mkForce {/rules = {/' "$mutated_production"
if validate_production_contract "$mutated_production"; then
  printf 'VM acceptance assets: unforced test PAM rules mutation passed\n' >&2
  exit 1
fi
mutated_runbook="$fixture/source/sleepy-vm-hyprland.md"
install -m 0600 -- "$repo_root/docs/runbooks/sleepy-vm-hyprland.md" "$mutated_runbook"
sed -i "/= \"\$original_disk_identity\"$/d" "$mutated_runbook"
if validate_rollback_contract "$mutated_runbook" >/dev/null 2>&1; then
  printf 'VM acceptance assets: removed rollback inode guard mutation passed\n' >&2
  exit 1
fi
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
      if test -e "$FAKE_VM_STATE_DIR/protected-started"; then
        printf '%s\n' running
      else
        printf '%s\n' "${FAKE_DOMAIN_STATE:-shut off}"
      fi
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
      metadata=
      qemu_extension=
      if test "${FAKE_XML_TOKEN_METADATA:-0}" = 1; then
        metadata="<metadata><vendor:record xmlns:vendor='https://example.invalid/vendor' token='do-not-persist'/></metadata>"
      fi
      if test "${FAKE_XML_QEMU_ENV:-0}" = 1; then
        qemu_extension="<qemu:commandline><qemu:env name='API_TOKEN' value='do-not-persist'/></qemu:commandline>"
      fi
      description=
      if test "${FAKE_XML_CREDENTIAL_TEXT:-0}" = 1; then
        description="<description>api_token=do-not-persist</description>"
      fi
      if test "${FAKE_XML_CREDENTIAL_PROSE:-0}" = 1; then
        description="<description>Password hunter2</description>"
      fi
      cat <<XML
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>Sleepy</name>
  <uuid>11111111-2222-4333-8444-555555555555</uuid>
  $description
  $metadata
  <os><nvram>$FAKE_NVRAM</nvram></os>
  <devices>
    <disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source file='$FAKE_DISK'/><target dev='vda' bus='virtio'/></disk>
    <graphics type='spice' autoport='yes'$secret_attribute/>
  </devices>
  $qemu_extension
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
  event)
    test "${1:-}" = Sleepy
    trap 'exit 0' TERM INT
    reported=0
    while true; do
      if test -e "$FAKE_VM_STATE_DIR/protected-started" && test "$reported" = 0; then
        printf '%s\n' 'event lifecycle: Started Booted'
        reported=1
      fi
      sleep 1
    done
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
    if test "${FAKE_START_PROTECTED_DURING_DRILL:-0}" = 1; then
      touch "$FAKE_VM_STATE_DIR/protected-started"
    fi
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
        elif test "$request" = regreet; then
          encoded=$(printf '%s\n' 1701 | base64 -w0)
        elif test "$request" = cage; then
          encoded=$(printf '%s\n' 1700 | base64 -w0)
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
      *pgrep*regreet*)
        printf '%s\n' regreet >"$FAKE_VM_STATE_DIR/qga-request"
        printf '{"return":{"pid":43}}\n'
        ;;
      *pgrep*cage*)
        printf '%s\n' cage >"$FAKE_VM_STATE_DIR/qga-request"
        printf '{"return":{"pid":44}}\n'
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

metadata_bundle="$fixture/metadata-baseline"
assert_rejected credential-metadata env PATH="$fake_bin:$PATH" FAKE_XML_TOKEN_METADATA=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$metadata_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$metadata_bundle"

qemu_env_bundle="$fixture/qemu-env-baseline"
assert_rejected credential-qemu-env env PATH="$fake_bin:$PATH" FAKE_XML_QEMU_ENV=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$qemu_env_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$qemu_env_bundle"

credential_text_bundle="$fixture/credential-text-baseline"
assert_rejected credential-text env PATH="$fake_bin:$PATH" FAKE_XML_CREDENTIAL_TEXT=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$credential_text_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$credential_text_bundle"

credential_prose_bundle="$fixture/credential-prose-baseline"
assert_rejected credential-prose env PATH="$fake_bin:$PATH" FAKE_XML_CREDENTIAL_PROSE=1 \
  "$repo_root/scripts/vm/capture-baseline.sh" --domain Sleepy --run-dir "$credential_prose_bundle" \
  --expected-system /nix/store/accepted-nixos-system-sleepy
test ! -e "$credential_prose_bundle"

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
jq -e '
  .verificationUuid == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" and
  .greetd == "active" and .regreet == "running" and
  .greeterCompositor == "cage-running" and
  .temporaryDomainRemoved == true and .protectedDomainStarted == false
' "$bundle/restore-verification.json" >/dev/null

guard_bundle="$fixture/protected-guard"
cp -a -- "$bundle" "$guard_bundle"
rm -f -- "$guard_bundle/restore-verification.json"
: >"$FAKE_VM_LOG"
assert_rejected protected-start-during-drill env PATH="$fake_bin:$PATH" \
  FAKE_START_PROTECTED_DURING_DRILL=1 \
  "$repo_root/scripts/vm/verify-restore.sh" --bundle "$guard_bundle" --domain Sleepy \
  --verification-domain Sleepy-restore-verification
test ! -e "$guard_bundle/restore-verification.json"
test ! -e "$FAKE_VM_STATE_DIR/defined"
rm -f -- "$FAKE_VM_STATE_DIR/protected-started" "$FAKE_VM_STATE_DIR/qga-request"

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
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' | base64 --decode >"$redacted"
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

signature_only="$fixture/signature-only.png"
printf '\211PNG\r\n\032\nnot-structurally-decodable\n' >"$signature_only"
chmod 0600 "$signature_only"
assert_rejected signature-only-png env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/signature-only-evidence" --label desktop \
  --redacted-framebuffer "$signature_only" --redacted-runtime "$runtime" --confirm-redacted \
  --reviewer local-owner --delete-after 2099-10-01

invalid_indexed_depth="$fixture/indexed-16-bit.png"
indexed_without_palette="$fixture/indexed-without-palette.png"
python3 - "$invalid_indexed_depth" "$indexed_without_palette" <<'PY'
import struct
import sys
import zlib

signature = b"\x89PNG\r\n\x1a\n"

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

def write(path, bit_depth, include_palette, scanline):
    ihdr = struct.pack(">IIBBBBB", 1, 1, bit_depth, 3, 0, 0, 0)
    parts = [signature, chunk(b"IHDR", ihdr)]
    if include_palette:
        parts.append(chunk(b"PLTE", b"\0\0\0"))
    parts.extend([chunk(b"IDAT", zlib.compress(scanline)), chunk(b"IEND", b"")])
    open(path, "wb").write(b"".join(parts))

write(sys.argv[1], 16, True, b"\0\0\0")
write(sys.argv[2], 8, False, b"\0\0")
PY
chmod 0600 "$invalid_indexed_depth" "$indexed_without_palette"
assert_rejected invalid-indexed-depth env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/invalid-indexed-depth-evidence" --label desktop \
  --redacted-framebuffer "$invalid_indexed_depth" --redacted-runtime "$runtime" --confirm-redacted \
  --reviewer local-owner --delete-after 2099-10-01
assert_rejected indexed-without-palette env PATH="$fake_bin:$PATH" FAKE_DOMAIN_STATE=running \
  "$repo_root/scripts/vm/collect-evidence.sh" --domain Sleepy \
  --run-dir "$fixture/indexed-without-palette-evidence" --label desktop \
  --redacted-framebuffer "$indexed_without_palette" --redacted-runtime "$runtime" --confirm-redacted \
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
