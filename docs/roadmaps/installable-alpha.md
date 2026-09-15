# Sleepy usable-alpha working plan

One active plan. Keep the existing NixOS / Hyprland / UWSM / Quickshell and
SDK/session/locker/shell boundaries. Install media remains a minimal network
TUI; NVIDIA, Bluetooth, gaming, development and Flatpak are explicit choices.
Generic defaults remain overridable. No custom compositor or package manager.

## Completed and verified

- [x] UEFI/GPT/ESP/Btrfs whole-disk TUI installation, real credentials, target
  identity/busy checks, error reporting and actual interruption cleanup.
- [x] Final image `97830de`: fresh install, three disk-only boots, real login,
  native idle/VT/DPMS lock recovery, shell/session crashes and offline desktop.
- [x] Everyday basics: terminal/file manager, PNG save/view/clipboard, dark GTK,
  original Fastfetch crescent, system status/menu and keyring persistence.
- [x] Real Flathub timer recovery and Software window. Earlier separately
  recorded diagnostics cover Kalk installation, Firefox portal and polkit.
- [x] Conservative absent-hardware doctor; real virtual-audio changes/hotplug
  and removal of network/audio observation loops.
- [x] Optional-profile evaluation matrix; actual Git/direnv project devShell in
  a new generation, no global language runtimes, offline rollback to the base.
- [x] Failed evaluation preserves boot entries/profile; settings, PNG and keyring
  survive both update and rollback boots. Final run passes 47 gates.

[Revision-bound final proof and limitations](../acceptance/usable-alpha.md).
Production source remains `97830de`; the keyboard-readiness runner is recorded
separately. Final integration still requires exact PR checks and repository
handoff. Remove disposable disks/build environments after retaining the verified
image and compact evidence; keep any reproducibility cache explicitly labelled.

## Next work, in dependency order

1. **Finish this handoff.** Merge the reviewed production candidate after exact
   CI, retain checksum/source graph and compact evidence, finish temp cleanup.
   Keep the earlier failed runs and distinguish the runner-only follow-up.
2. **Make recovery guided.** Extend the existing TUI beyond instructions and a
   terminal: identify an installed system read-only, show diagnostics and boot
   generations, and require explicit confirmation for a bounded repair.
   Gate: wrong/busy targets rejected; disposable broken-boot recovery; no
   arbitrary UI command execution or promise to restore erased personal data.
3. **Make updates select a reviewed candidate.** Preserve saved-config rebuild
   semantics; add version/channel metadata, verification and clear progress.
   Gate: rejected candidate, failed activation/boot and previous-generation
   recovery. Publishing releases or promoting public channels remains separate.
4. **Validate physical hardware and gaming.** AMD/Intel/NVIDIA/hybrid with
   explicit device IDs, Vulkan/32-bit graphics, video acceleration, controllers,
   microphone/Bluetooth, brightness/battery/suspend and monitor scale/VRR.
   Gate: actual hardware evidence and optional Steam/Gamescope smoke; no claim
   based only on the existing profile evaluation matrix.
5. **Encryption and public distribution.** Add a separately tested encrypted
   install path and establish reproducible public binary artifacts/cache,
   source revisions, checksums and short installation/recovery instructions.
   Gate: fresh encrypted install/unlock/recovery, public-only download/install
   and honest known issues. No release publication without authorization.

## Verification discipline

Start with behavioral regressions and then real integration. Keep timeouts and
security assertions meaningful. A cached derivation or source grep is not a
fresh boot. Use only task-created disposable disks; never modify the user's
installed OS. Re-review downstream Qt/Hyprland patches on upstream upgrades.
