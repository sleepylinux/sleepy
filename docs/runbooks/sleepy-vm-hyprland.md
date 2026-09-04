# Sleepy VM Hyprland acceptance and rollback runbook

## Scope and stop conditions

This runbook targets the exact system libvirt domain `Sleepy` through
`qemu:///system`. It is not evidence that acceptance has run. Record results in
`docs/acceptance/hyprland-sleepy-desktop.md` only after executing every gate.

Stop immediately if any of these is true:

- the root tree or a component revision differs from the reviewed candidate;
- an immutable input is not remote-fetchable or `flake.lock` does not select it;
- `Sleepy` is not shut off before baseline capture or restore;
- the libvirt UUID, disk target/source, NVRAM path, checksum, or backing chain
  differs from the captured manifest;
- the rollback verification domain already exists or cannot be removed;
- a build, login, full-v3-snapshot, service, lock, portal, framebuffer, or
  downgrade gate fails.

Never place a login password in a command line, environment variable, script,
report, shell history, journal excerpt, or evidence file. Enter credentials
only into ReGreet/PAM interactively.

## 1. Prove the immutable candidate before touching the VM

Use the committed public root tree with the reviewed GitHub component pins.
Do not use `path:` or `git+file:` overrides for this production gate.

```bash
git status --short
nix flake check --no-write-lock-file -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel \
  --no-link --no-write-lock-file -L
nix build .#checks.x86_64-linux.hyprland-production-vm \
  --no-link --no-write-lock-file -L
git diff --exit-code
git status --short
```

All commands must pass and both Git status checks must be empty. Record the
root commit, `flake.lock` SHA-256, all four component revisions, and resulting
NixOS toplevel. Do not continue from a locally overridden graph.

The automated production check drives the real ReGreet UI, submits the `lazy`
account, and requires ReGreet to launch the generated UWSM Hyprland desktop
entry. Its isolated test node deliberately uses `pam_permit` and contains no
credential. It therefore proves greeter selection/session plumbing, not real
password acceptance or rejection; those PAM cases remain mandatory interactive
gates in sections 5 and 6.

## 2. Record the current guest generation and shut down

Before shutdown, record only the resolved system path and generation number;
do not copy guest state or credentials into the host bundle.

```bash
readlink -f /run/current-system
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

Shut the guest down gracefully. On the host, require the exact offline state:

```bash
virsh --connect qemu:///system domuuid Sleepy
test "$(virsh --connect qemu:///system domstate Sleepy | xargs)" = "shut off"
```

Do not use `destroy` on the protected domain.

## 3. Capture the rollback bundle

Choose a new directory beneath a private, existing parent. The script refuses
to replace any path, resolves exactly one file-backed qcow2 disk, records the
inactive XML and backing chain, creates a flattened offline qcow2 copy, copies
NVRAM separately, verifies the copy, and writes only mode-0600 artifacts in a
mode-0700 directory.

Capture is deliberately fail-closed on inactive XML: credential-like tag or
attribute names; credential keywords anywhere in text, tails, or attribute
values (`pass`, `password`, `passwd`, `token`, `secret`, `credential`, API,
access, or private keys); bearer material; private-key headers; nonempty custom
metadata other than the exactly shaped standard libosinfo OS identifier; and
libvirt QEMU command/environment extensions abort the capture. This can reject
harmless descriptions, which is preferable to retaining possible credentials
in a rollback bundle.

```bash
run_parent=/var/lib/libvirt/sleepy-acceptance
sudo install -d -m 0700 "$run_parent"
run_id=$(date -u +%Y%m%dT%H%M%SZ)
baseline_dir="$run_parent/$run_id-baseline"
expected_system=/nix/store/REPLACE-with-recorded-nixos-system-sleepy-path

sudo scripts/vm/capture-baseline.sh \
  --domain Sleepy \
  --run-dir "$baseline_dir" \
  --expected-system "$expected_system"

sudo sh -c 'cd "$1" && sha256sum --check checksums.sha256' sh "$baseline_dir"
sudo jq . "$baseline_dir/manifest.json" >/dev/null
```

If capture fails, the script removes only its known incomplete files and never
marks the bundle complete. Investigate any explicitly reported incomplete
private directory; never treat it as rollback media.

## 4. Drill the bundle in an isolated verification domain

The protected `Sleepy` domain remains off. The verification script checks all
hashes before its first libvirt query, creates only the exact temporary domain
`Sleepy-restore-verification`, boots private disk/NVRAM copies, waits boundedly
for QEMU Guest Agent, verifies the recorded system path plus live ReGreet and
Cage processes, monitors the protected domain's UUID/offline state throughout,
powers down, identity-checks cleanup, records the temporary UUID, and undefines
only that temporary domain.

The rollback bundle itself remains mode `0700/0600`. The drill creates its
throw-away copies beneath `${TMPDIR:-/var/tmp}` and grants only the captured
libvirt QEMU uid directory traversal plus read/write ACLs on those two copies;
cleanup removes the ACL-bearing directory together with the temporary domain.

```bash
sudo scripts/vm/verify-restore.sh \
  --bundle "$baseline_dir" \
  --domain Sleepy \
  --verification-domain Sleepy-restore-verification

sudo jq -e \
  '.temporaryDomainRemoved == true and .protectedDomainStarted == false and
   (.verificationUuid | type == "string") and .regreet == "running" and
   .greeterCompositor == "cage-running"' \
  "$baseline_dir/restore-verification.json" >/dev/null
! virsh --connect qemu:///system dominfo Sleepy-restore-verification
test "$(virsh --connect qemu:///system domstate Sleepy | xargs)" = "shut off"
```

Do not activate the candidate until this drill passes.

## 5. Apply the candidate in the real guest

Transfer a clean `git archive` or fetch the exact public commit in the guest.
Re-run the immutable flake check and toplevel build inside the guest before
switching. Record the old and new system profile links and keep all bootloader
generations.

```bash
sudo nixos-rebuild test --flake .#sleepy-vm
sudo nixos-rebuild switch --flake .#sleepy-vm
sudo systemctl reboot
```

At ReGreet, choose the UWSM Hyprland entry and authenticate interactively as
`lazy`. Never automate or record the credential.

## 6. Runtime acceptance matrix

Require all of the following before marking the runtime JSON successful:

- ReGreet starts UWSM's Hyprland entry; Hyprland IPC is live and no Niri
  process, service, or managed configuration is active;
- `sleepy-session.service`, `sleepy-shell.service`, and
  `sleepy-locker.service` are active without restart loops; system and user
  failed-unit counts are zero;
- the first frame read from `desktop.sock` is schema version 3 and
  `fullSnapshot`, with independently degraded absent VM hardware;
- launcher, workspaces, notifications, dashboard/sidebar, theme/wallpaper,
  OSD and window actions behave through their documented native providers;
  network uses fixed-argument `nmcli`, audio uses native PipeWire, and protected
  session/recording operations use typed Sleepy IPC;
- daemon and shell restart independently and recover automatically;
- incorrect/empty lock authentication, shell crash, daemon crash, locker
  fail-safe, monitor coverage, suspend/resume, and logout return remain secure;
- GTK file chooser, Hyprland screenshot/screencast portal, and PipeWire
  screencast work without competing backends.

Create a mode-0600 *redacted summary*, not raw command output. It must conform
to the schema exercised by `checks/vm-acceptance-assets-test.sh`: exact
candidate commits, unit states and failure counts, Hyprland/Niri state, v3
snapshot metadata, and every boolean in the functional matrix. It must contain
no SSID, notification text, device name, document/home path, credential, or
raw journal field.

## 7. Redacted framebuffer evidence

Capture raw framebuffer images only into a temporary mode-0700 staging
directory outside the repository. Files are mode 0600. Inspect and redact
SSIDs, notification text, paths, device names, and unrelated content before
collection. The collector deliberately rejects raw capture and accepts only a
PNG the reviewer explicitly confirms as redacted.

Required views are ReGreet, unlocked desktop, launcher, dashboard/sidebar,
lock screen, and recovered desktop after daemon/shell restart. For each view:

```bash
evidence_dir="$run_parent/$run_id-evidence-unlocked"
sudo scripts/vm/collect-evidence.sh \
  --domain Sleepy \
  --run-dir "$evidence_dir" \
  --label unlocked-desktop \
  --redacted-framebuffer /absolute/private-staging/unlocked-redacted.png \
  --redacted-runtime /absolute/private-staging/runtime-redacted.json \
  --confirm-redacted \
  --reviewer REPLACE-reviewer-id \
  --delete-after REPLACE-YYYY-MM-DD
sudo sh -c 'cd "$1" && sha256sum --check checksums.sha256' sh "$evidence_dir"
```

Delete raw staging captures immediately after visual review. Keep redacted
artifacts only until the recorded deletion date unless the user explicitly
authorizes longer retention.

## 8. Downgrade and return

From the bootloader, boot the exact prior Niri generation recorded before the
switch. Confirm essential login and byte-for-byte hashes of legacy user state.
Do not mutate or regenerate it. Then boot the candidate Hyprland generation
again and repeat readiness, full snapshot, service health, and recovered
desktop framebuffer checks.

Only after returning successfully may the acceptance report change from
`PENDING` to `PASS`.

## 9. Failure rollback

Keep `Sleepy` shut off. First re-run bundle checksums and confirm the current
domain UUID and original source paths exactly match `manifest.json`. Stop on
any mismatch. Prepare verified replacement files beside the originals before
moving anything; never overwrite an unresolved path or symlink.

```bash
sudo sh -c 'cd "$1" && sha256sum --check checksums.sha256' sh "$baseline_dir"
test "$(virsh --connect qemu:///system domstate Sleepy | xargs)" = "shut off"
test "$(virsh --connect qemu:///system domuuid Sleepy)" = \
  "$(sudo jq -r .domain.uuid "$baseline_dir/manifest.json")"

original_disk=$(sudo jq -r .disk.originalSource "$baseline_dir/manifest.json")
original_target=$(sudo jq -r .disk.originalTarget "$baseline_dir/manifest.json")
original_nvram=$(sudo jq -r .nvram.originalSource "$baseline_dir/manifest.json")
test -f "$original_disk" && test ! -L "$original_disk"
test -f "$original_nvram" && test ! -L "$original_nvram"
original_disk_identity=$(stat -Lc '%d:%i' -- "$original_disk")
original_nvram_identity=$(stat -Lc '%d:%i' -- "$original_nvram")
live_disk=$(virsh --connect qemu:///system domblklist --inactive --details Sleepy |
  awk -v target="$original_target" '$2 == "disk" && $3 == target { print $4 }')
live_nvram=$(virsh --connect qemu:///system dumpxml Sleepy --inactive |
  python3 -c 'import sys; import xml.etree.ElementTree as ET; nodes=ET.parse(sys.stdin).getroot().findall("./os/nvram"); sys.exit("expected one NVRAM path") if len(nodes) != 1 or not nodes[0].text else print(nodes[0].text)')
test "$live_disk" = "$original_disk"
test "$live_nvram" = "$original_nvram"

rollback_id=$(date -u +%Y%m%dT%H%M%SZ)
disk_candidate="${original_disk}.restore-${rollback_id}"
nvram_candidate="${original_nvram}.restore-${rollback_id}"
failed_disk="${original_disk}.failed-${rollback_id}"
failed_nvram="${original_nvram}.failed-${rollback_id}"
for path in "$disk_candidate" "$nvram_candidate" "$failed_disk" "$failed_nvram"; do
  test ! -e "$path" && test ! -L "$path"
done

sudo qemu-img convert -p -O qcow2 \
  "$baseline_dir/disk.qcow2" "$disk_candidate"
sudo qemu-img check "$disk_candidate"
sudo cp --reflink=auto --sparse=always -- \
  "$baseline_dir/nvram.fd" "$nvram_candidate"
sudo chown \
  "$(sudo jq -r .disk.originalUid "$baseline_dir/manifest.json"):$(sudo jq -r .disk.originalGid "$baseline_dir/manifest.json")" \
  "$disk_candidate"
sudo chmod "$(sudo jq -r .disk.originalMode "$baseline_dir/manifest.json")" \
  "$disk_candidate"
sudo chown \
  "$(sudo jq -r .nvram.originalUid "$baseline_dir/manifest.json"):$(sudo jq -r .nvram.originalGid "$baseline_dir/manifest.json")" \
  "$nvram_candidate"
sudo chmod "$(sudo jq -r .nvram.originalMode "$baseline_dir/manifest.json")" \
  "$nvram_candidate"

# The image conversion can be long. Treat every identity and path fact above
# as stale and resolve it again immediately before the first destructive move.
# Abort if the protected domain started, was redefined, or changed storage.
final_state=$(virsh --connect qemu:///system domstate Sleepy | xargs)
final_uuid=$(virsh --connect qemu:///system domuuid Sleepy)
final_disk=$(virsh --connect qemu:///system domblklist --inactive --details Sleepy |
  awk -v target="$original_target" '$2 == "disk" && $3 == target { print $4 }')
final_nvram=$(virsh --connect qemu:///system dumpxml Sleepy --inactive |
  python3 -c 'import sys; import xml.etree.ElementTree as ET; nodes=ET.parse(sys.stdin).getroot().findall("./os/nvram"); sys.exit("expected one NVRAM path") if len(nodes) != 1 or not nodes[0].text else print(nodes[0].text)')
test "$final_state" = "shut off"
test "$final_uuid" = "$(sudo jq -r .domain.uuid "$baseline_dir/manifest.json")"
test "$final_disk" = "$original_disk"
test "$final_nvram" = "$original_nvram"
test -f "$original_disk" && test ! -L "$original_disk"
test -f "$original_nvram" && test ! -L "$original_nvram"
test -f "$disk_candidate" && test ! -L "$disk_candidate"
test -f "$nvram_candidate" && test ! -L "$nvram_candidate"
test "$(stat -Lc '%d:%i' -- "$original_disk")" = "$original_disk_identity"
test "$(stat -Lc '%d:%i' -- "$original_nvram")" = "$original_nvram_identity"

sudo mv -- "$original_disk" "$failed_disk"
sudo mv -- "$original_nvram" "$failed_nvram"
sudo mv -- "$disk_candidate" "$original_disk"
sudo mv -- "$nvram_candidate" "$original_nvram"
sudo virsh --connect qemu:///system define "$baseline_dir/domain.xml"
```

Boot and verify the recorded generation/ReGreet before deleting anything.
Retain the bundle and `.failed-*` files until the failure is resolved and the
user authorizes cleanup.
