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
- [x] Image `afd713c`: fresh installation, two disk-only password boots and
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
The final ISO is 820 MiB. Keep the verified artifact and labelled signed cache;
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
2. **Reviewed-candidate updates — active implementation.** Keep saved-config rebuild semantics. The
   next implementable slice is an explicitly approved immutable candidate,
   staged while preserving installation settings and system.stateVersion,
   built before selection for the next boot. Keep the installation configuration
   unchanged and retain the evaluated source in each generation's closure so
   rollback and the next rebuild agree. Backend, TUI and VM gates are being
   implemented. Source253 passed a separate fresh installation and offline TUI
   repair (40 gates/two password boots). The update run passed invalid hash,
   invalid config, real builder interruption and candidate password boot, then
   exposed a lost lock request after daemon reconnection. Fix that stale-generation
   path with bounded idempotent-lock handling before completing candidate
   rebuild/GC-root/rollback acceptance; keep the failed run failed. Gates: rejected
   or changed candidate, concurrent config edits, offline/build failure,
   interruption, failed boot and previous-generation password desktop recovery.
   A content hash proves identity, not maintainer approval. Automatic channels
   require an approved signing/catalog/promotion policy; none exists yet.
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
