# Sleepy usable-alpha working plan

One plan. Preserve NixOS / Hyprland / UWSM / Quickshell and the
SDK/session/locker/shell boundaries. Keep the network installer a minimal TUI;
NVIDIA, Bluetooth, gaming, development and Flatpak remain explicit choices.
Generic defaults stay overridable. No custom compositor or package manager.

## Completed and verified

- [x] UEFI/GPT/512 MiB ESP/Btrfs TUI installation with real credentials,
  regional settings, optional profiles, diagnostics and interruption cleanup.
- [x] Actual mounted-descendant rejection before preflight, descendant identity
  fingerprinting and changed-target checks. The lsblk topology regression is
  fixed; older installer images are superseded.
- [x] Image `7c75fa8`: fresh installation, two disk-only password boots and
  40 gates. Delete boot entries on the disposable disk, prove failed boot,
  inspect/cancel with unchanged GPT and full partition hashes, then restore
  through the offline TUI and retain configuration, profile and personal files.
- [x] New recovery image also repairs the earlier public-only installed229
  disk. Historical failed/interrupted investigations keep their original status.
- [x] Everyday desktop: terminal/file manager, PNG save/view/clipboard, dark GTK,
  original crescent Fastfetch, system status/menu, first-boot welcome and keyring.
  Real password lock, VT/layout/input-DPMS, shell/session crashes and offline
  persistence pass. Idle process/memory samples remain stable.
- [x] Historical978 run: 47 gates, three boots, real Flathub timer/Software,
  failed evaluation preserving boot state, Git/direnv/pinned project devShell in
  a second generation, no global language runtimes, offline rollback. Earlier
  separate diagnostics cover Kalk, Firefox portal, polkit and virtual audio.
- [x] Component fixes and source review, behavioral regressions, packaged tests,
  exact image/checksum/pins and revision-bound VM evidence. Production PR #10
  and [PR #11](https://github.com/sleepylinux/sleepy/pull/11) merged; the latter's
  exact `27c99c4` CI run 34955692745 passed all jobs, including strict sandbox
  topology tests and production VM checks.

[Acceptance and exact limits](../acceptance/usable-alpha.md),
[installation](../runbooks/installable-alpha.md), [recovery](../recovery.md).
The current installer ISO is 821 MiB. Keep the verified artifact and labelled signed cache;
remove disposable disks, credentials and the task-owned builder after validation.

## Next cycle, in dependency order

1. **Physical hardware acceptance — needs a dedicated target.** Exercise
   AMD/Intel/NVIDIA/hybrid, Vulkan/32-bit graphics, video acceleration,
   controllers, microphone/Bluetooth, brightness/battery/suspend and monitors
   with scale/refresh/VRR. Run optional Steam/Gamescope smoke on real hardware.
   The current host's RTX 5070 is bound to its installed NVIDIA driver, with no
   assignable IOMMU group exposed; no repository self-hosted runner is registered.
   Do not unbind or alter that host OS. Configuration evaluation and virtual audio
   are useful evidence, not physical GPU or suspend acceptance.
2. **Reviewed-candidate updates — final VM acceptance active.** Backend and TUI
   now stage approved immutable sources while preserving installed settings and
   the running system. Each generation retains its source; GC cleanup and the
   ready/rollback lifecycle have behavioral regressions. Source d16 passed fresh
   installation, two password boots, rejected hash/config, actual builder SIGTERM,
   candidate selection, same-candidate cleanup and saved rebuild. It then exposed
   rollback auto-reexec evaluating the wrong flake output. Fix8624092 bypasses
   evaluation, with actual pinned-tool tests for absent/broken configuration;
   the new862→d408 full installed/updated/offline-rollback VM is running.
   Desktop lock reconnection and session PID-readiness fixes passed full component
   CI and merged as desktop PR10/session PR14. Root CI independently found cleanup
   permissions after its source-identity check passed; repair only the copied
   fixture. Source7c75 also passed40 recovery gates with two disk password boots.
   Keep failed/interrupted runs labelled. Do not promote this to a public channel:
   a content hash proves identity, and signing/catalog/promotion policy remains
   a separate decision.
3. **Complete the session capture provider.** Print already uses native
   Quickshell screencopy and Swappy. The separate SDK capture action expects an
   unimplemented helper; keep doctor honest until consent/output contracts and
   actual capture are tested. Do not alias its status to the Print picker.
4. **Encryption and public distribution.** Add a separate encrypted
   install/unlock/recovery branch. Prepare reproducible public binary artifacts,
   source revisions/checksums, short docs and honest known issues. Validate a
   current public-only installation. Release publication and public channel
   promotion still require separate authorization.

## Verification discipline

Behavioral regressions precede integration; cached derivations and source grep
are not fresh boots. Keep failures visible and success claims tied to exact
image/runner revisions. Use only task-created VM disks. Do not modify the user's
installed OS. Re-review downstream Qt/Hyprland patches on upstream upgrades.
