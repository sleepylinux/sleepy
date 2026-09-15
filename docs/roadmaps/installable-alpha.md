# Sleepy usable-alpha working plan

One active plan. Reuse the existing NixOS / Hyprland / UWSM / Quickshell
boundaries. No custom compositor, package manager, browser or terminal.
Install media stays a small network TUI; NVIDIA, Bluetooth, gaming, development
and Flatpak remain explicit choices. Host preferences remain overridable.

## Completed foundation

- [x] TUI installation: UEFI/GPT/ESP/Btrfs, real credentials, disk identity checks.
- [x] Installed-disk VM: login, desktop/apps, settings persistence, crash recovery,
  failed update preservation and previous-generation boot without networking.
- [x] Read-only doctor: validated bounded snapshots, private-data redaction,
  real installed-VM offline/daemon-restart checks and independent review.
- [x] Remove old VM copies, intermediate images and build caches; preserve the
  verified ISO and compact revision-bound evidence.

Installer proof: [acceptance](../acceptance/installable-alpha.md).
Doctor proof and observed provider errors: [acceptance](../acceptance/doctor.md).
Root doctor PR #9 and session PR #10 are merged. Root CI run 34910938757
passed all checks, including fresh production and update-safety VM gates.

## Next deliverables, in dependency order

1. **Usable hardware state.** Correct valid no-audio/no-battery/no-Bluetooth
   states without hiding malformed replies or real timeouts. Gate: regression
   fixtures plus a real VM with virtual audio, and absent/disabled hardware.
2. **Everyday workflow.** Verify file manager, browser/file portals, clipboard,
   screenshots with an obvious key, keyring/polkit and optional Software.
   Flathub must recover after offline first boot. Gate: real UI actions,
   saved PNG and clipboard roundtrip, reboot persistence, offline-to-online.
3. **Consistent appearance.** Original crescent ASCII in Fastfetch; coherent
   dark application theme, icons and terminal palette using existing tokens.
   Gate: 80/120-column and monochrome renders, real desktop screenshots at
   two sizes, readable controls and preserved per-host overrides.
4. **Optional profiles.** Keep AMD/Intel defaults and explicit NVIDIA selection;
   validate gaming/32-bit graphics and development/direnv choices. Improve
   hybrid profiles only with explicit device IDs. Gate: Nix evaluation matrix,
   VM launch checks, and project devShell use without global language runtimes.
5. **Updates and recovery without Nix knowledge.** Build on sleepy-system's
   existing generations/rebuild/rollback, add actionable status/progress and
   reviewed candidate selection. Gate: real installed-system update, rejected
   or failed candidate, preserved settings, previous generation after reboot.
   Public channel promotion requires separate release authorization.
6. **Reproducible alpha handoff.** Build the final TUI image; record checksums,
   source graph, user/contributor instructions and honest known issues.
   Gate: fresh ISO-to-installed-disk acceptance of the final production graph,
   independent review, exact-head CI and cleanup of temporary disks/builds.

Recent bounded diagnostics on the retained installed disk now cover real
Software → Flathub Kalk installation and calculation, Print/save/view and
Shift+Print clipboard, generation-list/menu cancellation, and native dark-locker
VT return/input/PAM unlock with the scoped Qt fix. These use temporary runtime
overrides; Firefox FileChooser and real-password polkit authorization also pass.
Desktop PR #8 is merged after exact CI and a 20-minute packaged-shell soak
(121 samples, zero restarts). Image `bfa319a` completed fresh TUI installation, disk-only boot, real login
and Flathub retry, then failed to display an idle lock created on an inactive
VT. The PipeWire observation-client loop is fixed and verified in an installed-VM
A/B (session PR #12 merged). The compositor activation correction passed cold idle-lock, real-password and
shell-crash/DPMS/VT comparisons and is now wired into the production default.
Empty Wayland app metadata no longer rejects the entire provider (session PR #13
merged). Next: freeze the corrected source graph and repeat fresh installation
and the full daily/update/rollback gate. The first corrected-image install
exposed duplicate Hyprland portal units; d047afd removes the redundant
registration and the new default/Flatpak assembled-unit regression passes. Keyring persistence, crash/DPMS wake
and update/rollback still require the corrected final image gate.
[Revision-bound evidence](../acceptance/usable-alpha.md).

## Verification and limits

Keep one current disposable installed disk and one active build environment;
remove superseded outputs after retaining compact evidence. Start with targeted
regressions, then required integration gates. Source checks and cached builds
are not fresh VM boots. Treat each discovered failure as a bug to explain;
never relax assertions merely to obtain green CI.

Physical GPUs/hybrid switching, real microphone/Bluetooth, battery/brightness,
suspend, high-refresh/VRR and Secure Boot need explicit hardware evidence.
They remain unverified when only simulated. Encryption follows the working
base install. Publishing releases, promoting public channels and modifying an
actual installed OS still require the user's separate authorization.
