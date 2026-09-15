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
- [x] Historical image `afd713c` also repairs the earlier public-only installed229
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

- [x] Reviewed-candidate updates: image `8624092` → candidate `d40861d` passed
  44 gates and three real-password disk boots, including real builder
  interruption, candidate selection, saved rebuild, repeated preparation/GC
  cleanup, offline rollback and future-update validation. These revisions share
  runtime code; a separate `88a87c5` → `d40861d` changed-runtime test passed
  43 gates and three password boots. Pinned-tool regressions also prove rollback
  works with absent/broken saved configuration. Integration and exact CI are
  tracked in [PR #12](https://github.com/sleepylinux/sleepy/pull/12).
- [x] Final visual inspection: custom ASCII crescent and compact Fastfetch Disk
  output fit the actual 1280×800 desktop. Desktop PR #10/session PR #14 merged
  after full component CI and automated review. The source-copy cleanup check
  also passes as a non-root user. No public update channel has been promoted.

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
2. **Complete the session capture provider.** Print already uses native
   Quickshell screencopy and Swappy. The separate SDK capture action expects an
   unimplemented legacy helper. A separate opt-in capture v1 endpoint now has
   typed asynchronous jobs, cancellation and bounded temporary PNG publication;
   session and SDK changes passed full CI and merged. The existing picker supplies
   visible region consent through an anonymous image descriptor. Native writer,
   QML lifecycle, real daemon shutdown and production packaging checks pass.
   Image `f279883` installed and booted without ISO, but capture acceptance
   failed: one run returned an unexplained doctor error; a second reproduced
   Escape failure after a VT roundtrip. The capture service now inherits the
   existing Qt focus fix, pending rebuilt-image verification. Keep both failed
   reports in `docs/acceptance/assets/capture-f279883`. Keep legacy doctor honest and
   do not alias its status to the Print picker.
3. **Encryption and public distribution.** Add a separate encrypted
   install/unlock/recovery branch. Prepare reproducible public binary artifacts,
   source revisions/checksums, short docs and honest known issues. Validate a
   current public-only installation. Release publication and public channel
   promotion still require separate authorization.

## Verification discipline

Behavioral regressions precede integration; cached derivations and source grep
are not fresh boots. Keep failures visible and success claims tied to exact
image/runner revisions. Use only task-created VM disks. Do not modify the user's
installed OS. Re-review downstream Qt/Hyprland patches on upstream upgrades.
