# Sleepy MVP roadmap and next-agent handoff

Updated 2026-09-15. This is the single active working plan; update it in place.
Read this before starting another audit or creating a new plan. The current task
is integration and handoff, not permission to resume unattended feature work.

## Product and boundaries

A small x86_64 UEFI **TUI network installer**, no live desktop or graphical
installer. Preserve NixOS, Hyprland, UWSM, Quickshell and the SDK/session/locker/
shell boundaries. NVIDIA, Bluetooth, gaming, development and Flatpak are explicit
unchecked installer choices. Keep generic defaults overridable; personal
settings belong in host profiles. Keep the custom crescent ASCII Fastfetch logo
and existing design tokens. Do not build a compositor or package manager.

Local changes, branches, commits, pushes, PRs and merges are authorized. Release
publication, public update-channel promotion and changes to the user's installed
OS require separate permission. Destroy only task-created disposable VM disks.
Do not substitute another account's approval for actual review; identify
AI-assisted reviews honestly. Never log passwords or put them in QML/argv.

## Authoritative starting state

- [Root PR #12](https://github.com/sleepylinux/sleepy/pull/12) merged with exact-head
  CI 34979176753 passing. Verified baseline and update/rollback evidence are in
  [usable-alpha acceptance](../acceptance/usable-alpha.md).
- [Desktop PR #11](https://github.com/sleepylinux/sleepy-desktop/pull/11) merged as
  `f7bcf7af7878df3565702d205c189178ec2fbf10`; reviewed/pinned code is `7958ed0`.
  SDK capture PR #9 and session PR #15 also merged. Do not update pins merely
  because merge SHAs differ: compare trees and relevant changes.
- [Root PR #14](https://github.com/sleepylinux/sleepy/pull/14) merged into its base
  `feat/async-capture` as `1d3de178a6f4966602040c263969260ec49b5acf`.
  [Root PR #13](https://github.com/sleepylinux/sleepy/pull/13) carries the combined
  capture/encryption implementation and this handoff to `main`. Check its actual
  merged state and latest CI before selecting the next source revision.
- Root PR #6 is an older separate stabilization effort, not part of this merge.
  Do not merge it blindly over the current architecture.
- **Merged implementation is not installed-VM acceptance.** No public release
  or update channel has been promoted. The latest encrypted/capture changes are
  experimental until the gates below pass on a freshly built image.

## What is actually verified

| Area | Evidence and limits |
| --- | --- |
| Base installation and daily desktop | Image `86240920109f37263c3260ea501c2a15fafa7dd8`: unencrypted TUI install, disk-only password boots, lock/VT/layout/DPMS, shell/session crashes, terminal/file manager, saved PNG/clipboard, keyring, Fastfetch, settings and offline persistence. |
| Updates | `8624092` to candidate `d40861d`: 44 gates, three boots. Separate changed-runtime `88a87c5` to `d40861d`: 43 gates, three boots. Builder interruption, rejected candidates, saved rebuild, GC ownership and offline rollback. |
| Boot recovery | `7c75fa8`: 40 gates, two boots; damaged EFI entries, actual failed boot, offline TUI inspect/cancel with unchanged partition hashes, repair and preserved user state. This is unencrypted recovery evidence. |
| Optional apps/development | Historical `978` run: real Flathub/Software, Git/direnv/pinned devShell and rollback. Recheck on the final candidate; do not treat old evidence as coverage of every new revision. |
| Capture v1 | SDK/session/desktop tests and component CI pass. Actual `f279883` install passed daily gates but failed capture responsiveness once; a separate disk boot reproduced ignored Escape after VT switching. Neither is a capture acceptance pass. |
| Encryption | Image `0d24e593a7072c4940115d417aff225ec069146e` installed through the real TUI and booted without ISO to the LUKS prompt. Wrong-passphrase feedback was absent, so the run failed before authenticated desktop/recovery. |

Preserve [capture failures](../acceptance/assets/capture-f279883/) and
[encrypted failure](../acceptance/assets/encrypted-0d24e59/). Their manifests bind
screenshots/reports to revisions. The old verified image is 821 MiB; the recent
experimental images are 822 MiB. Never relabel old images as containing new fixes.

## First work: finish the pending VM acceptance

1. **Rebuild after `d77dd1f`, then verify encrypted boot feedback.** That commit
   adds an encrypted-only `systemd-cryptsetup@` drop-in with
   `SYSTEMD_LOG_TARGET=console` and `StandardError=journal+console`. Exact pinned
   systemd 261.1 emits a real incorrect-passphrase error through native logging;
   the old boot displayed only a repeated prompt. All 24 targeted backend
   validation cases pass (root-only case separately), and full NixOS evaluation
   confirms the drop-in. **The fix has not been boot-tested.** Keep the runner's
   explicit rejection and subsequent new-prompt checks; do not replace them
   with a sleep or blindly enter the correct secret.
2. **Complete capture on that installed desktop.** Commit `a075bbd` gives the
   capture-launching session daemon the existing Qt Wayland focus library.
   Packaged session checks pass; real Escape after a VT roundtrip is unverified.
   Exercise visible consent, responsive doctor/locker, Escape, API cancellation,
   dragged-region PNG dimensions/permissions/viewer and daemon-crash cleanup.
   If doctor fails, retain its JSON and bounded session journal; optional legacy
   screenshot unavailability is not itself a doctor failure. Native Print and
   capture v1 are separate paths; do not claim one proves the other.
3. **Finish encrypted offline boot repair and repeat the unencrypted default.**
   Prove wrong unlock leaves partitions unchanged and no mapper behind; read-only
   inspection/Back preserves hashes; confirmed repair restores a disk-only boot
   and real password login. Verify user settings/PNG persistence. Then test a
   fresh installation with encryption and all optional software left off.

The last runner passed all 50 host protocol tests, but these are not VM proofs.
The earlier `a075bbd` run failed before its interruption fixture reached mounted
filesystems; backend diagnostics were missing. The next `0d24e59` run passed
that same interruption/cleanup gate. The earlier cause remains unproven. New
runner code retains bounded redacted backend diagnostics and fails promptly.

### Reproduction from a clean checkout

Use a checkout containing this handoff; record actual HEAD, pins and ISO hash.
With Nix and flakes enabled, from the repository root:

```sh
python3 -m unittest discover -s scripts/vm -p 'test_*.py'
sleepy_revision=$(git rev-parse HEAD)
nix build .#checks.x86_64-linux.installer --no-link -L
nix build .#installer-iso --out-link result-installer -L
sha256sum result-installer/iso/*.iso
python3 scripts/vm/installable-alpha.py \
  --iso result-installer/iso/sleepy-0.1.0-alpha-x86_64-linux.iso \
  --image-source-revision "$sleepy_revision" \
  --output "work/encrypted-$sleepy_revision" --memory 6144 --keyboard ru \
  --interrupt-install --daily-usability --capture-jobs \
  --encrypt-install --boot-recovery
```

Require QEMU/OVMF, pexpect, Pillow, Tesseract and a new output directory. KVM is
available in the current workspace; TCG is a fallback elsewhere. Set `--firmware`
and `--vars` if your OVMF paths differ from the runner defaults. This command
uses public sources. The [runbook](../runbooks/installable-alpha.md) explains the
optional signed local cache; add both cache arguments when using it, and record
that the run was cache-assisted. Do not substitute that run for public-only
acceptance. If an early gate fails, preserve its failed result before a separately
labelled diagnostic boot; do not skip the gate and call the full run successful.

Active code: `packages/sleepy-installer/{backend,recovery,tui,recovery_tui}.py`,
`modules/home/session/default.nix`, and
`scripts/vm/{installable-alpha,encrypted_install,capture_jobs,boot_recovery}.py`.
Use the existing behavioral tests and component boundaries rather than rewriting
working architecture. There is no global Python runtime in the installed base;
guest fixtures must use the interpreter already resolved by the runner.

## Remaining product roadmap

| Priority | Work | Completion evidence |
| --- | --- | --- |
| P0 | Finish the pending fresh encrypted and default installation gates above. | Image to TUI to shutdown to disk-only unlock/login/desktop; strict capture, crash, offline, persistence and recovery reports with exact source/hash. No unexplained failure relabelled as success. |
| P1 — hardware | Validate AMD/Intel/NVIDIA/hybrid profiles, Vulkan/video/32-bit acceleration, network, Bluetooth, PipeWire/microphone, brightness/battery/suspend, monitors/scale/refresh/VRR. Improve read-only `sleepyctl doctor` only where real diagnostics show gaps. | Dedicated hardware reports plus regression tests for fixes. Virtual audio/config evaluation do not prove physical GPU, battery or suspend behavior. |
| P1 — daily desktop | Recheck file manager, portals, clipboard/screenshots, secrets/polkit, optional Flatpak/Flathub and graphical Software. Fix concrete first-boot/offline/restart and keyboard/accessibility defects. | Actual applications and permission dialogs work after fresh login, session restart and offline reboot; errors are actionable. |
| P2 — gaming | Validate optional Steam/Proton, GameMode, Gamescope, MangoHud, controllers and required 32-bit graphics. Keep proprietary/large packages opt-in. | Representative real game/controller runs on the selected hardware, with versions and limitations recorded. |
| P2 — development | Recheck Git/SSH, direnv/nix-direnv, pinned project devShells, containers and editor integration. Do not install all language runtimes globally. | A fresh project builds/runs, secrets remain private, container/editor workflows work and the base profile stays minimal. |
| P2 — updates/recovery | Repeat changed-runtime update, failed update, previous-generation boot and source-preserving rollback on the final installed candidate; cover encrypted installations too. Keep verified candidates/channels rather than uncontrolled stable updates. | Real interrupted/failed build cannot replace the working boot state; offline previous-generation login and preserved user data. Public promotion needs permission. |
| P3 — identity | Refine existing controls/tokens, TUI spacing/focus/help and first-boot UX. Preserve custom crescent Fastfetch, contrast, keyboard navigation and reduced-motion behavior. | Reviewed screenshots at supported sizes plus actual keyboard-only flows; no appearance change breaks installation, unlock, lock or recovery. |
| P3 — public alpha | Produce reproducible artifacts, checksums, source/pin records, concise install/contributor docs, release notes and honest known issues. Measure image size and perform a current public-only installation. | Another clean environment can build/install the named source; distributable artifacts match hashes and acceptance records. Publication is a separate authorized step. |

Hardware is a real external dependency, not a reason to stall P0 or software work:
the current host's RTX 5070 belongs to its running OS, no assignable IOMMU group
was exposed, and no repository self-hosted runner was registered. Recheck access
when resuming; do not unbind the host GPU or change its installed OS.

## Current workspace and cleanup

- Workspace parent: `/home/lazy/orca/workspaces/sleepy`. `razvitie` is the user's
  working checkout; `candidate-updates` and `encrypted-install` are retained
  implementation worktrees. Check branches/status before editing or deleting.
- Task Docker container `sleepy-alpha-build` and local cache server were stopped.
  Nix volume `sleepy-alpha-nix` remains; do not rebuild the toolchain unnecessarily.
  The container's original working directory was removed: always pass `docker
  exec -w /workspace/...`. For container builds, archive the chosen git revision
  into a clean directory and use `nix build path:.#...`; do not copy VM sockets,
  credentials or ignored work data into a flake source.
- Optional signed cache and ISO artifacts live in `razvitie/work/artifacts`.
  Cache directory: `sleepy-cache-97830de`; public key is in its `public-key` file.
  Keep signature verification enabled. Never export a private signing key.
- Disposable test disks and test credentials were deleted after evidence capture.
  Start a fresh VM; old `work/vm-*` reports do not imply a reusable disk exists.
  Retain compact reports/screenshots; remove task disks and unused build outputs
  after validation. Stop background services when handing back the machine.
- `/var/lib/libvirt/images/Sleepy.qcow2` is an older user VM, not a disk created
  by this task. Its deletion was not confirmed. Preserve it and unrelated Docker
  database volumes, projects and user snapshots.

## Definition of done

The MVP is not complete merely because these PRs merge or CI turns green. Close
each roadmap item with behavior evidence at its actual scope; distinguish
implemented, tested, blocked and deferred. Link exact revisions, commands,
checksums, logs and useful screenshots. Finish with the remaining limitations
and the next actionable task, rather than a new chain of plans and summaries.
