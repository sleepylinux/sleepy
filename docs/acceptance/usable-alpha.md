# Usable alpha validation in progress

This record covers the daily-usability candidate. It does not replace the
[accepted installer ISO](installable-alpha.md) until a complete installed-disk
run passes for the new production graph.

## Implemented and targeted checks

- Conservative absent-hardware providers: session `004e81d`, component CI
  [34911942420](https://github.com/sleepylinux/sleepy-session/actions/runs/34911942420)
  passed. Follow-up `2e85655` fixes the captured UPower absence response;
  its signed runtime was checked on the existing disposable disk below.
  Fresh combined-image acceptance remains pending.
- Original terminal crescent: artwork `ac3feed`, merged PR #6; exact-head CI and
  real Fastfetch 80/120-column plus monochrome renders passed.
- Shared GTK/terminal appearance, image viewer, Fastfetch and screenshot keys:
  real Home Manager override assertions evaluate successfully. Actual combined
  installed-desktop rendering and screenshot roundtrips are pending.
- Optional hardware/software profiles: base, Bluetooth, Flatpak, development,
  gaming, NVIDIA and combined configurations evaluate successfully. Physical
  hardware and real game performance are not covered by this matrix.

## Flatpak registration regression

Production change `ad9e3599fcf0b071765115310352663ce7b1503a` was exercised in
separate fresh disposable KVM guests. The old unit failed to retry registration
within 30.30 seconds after the controlled remote operation recovered. The new
unit passed in 69.46 seconds: retry after error, no repeat after success, bounded
stalled process while login remains independent, child cleanup and recovery.

The test replaces only the remote operation and accelerates the timer interval
to two seconds. Production process deadlines remain 45 seconds to start and
five seconds to stop. This proves systemd scheduling and cleanup; public
Flathub and graphical Software installation require separate acceptance.

Reproduce with `nix build .#checks.x86_64-linux.flatpak-recovery --max-jobs 1 -L`.
[Provenance](assets/usable-alpha/flatpak-recovery.txt),
[old-unit failure](assets/usable-alpha/flatpak-recovery-red.log),
[new-unit pass](assets/usable-alpha/flatpak-recovery-green.log).

## Combined VM

Candidate ISO `7231d4b2bf320440365b0f51a323f3466c724dd1` completed real TUI
installation, installed-disk boot, password login, application mapping and crash
recovery. A first boot with the NIC disconnected before firmware execution
failed its first Flathub registration, then the unchanged production timer
registered the real public remote after networking returned.

The combined run **failed** waiting for the visible password field after
locking. The protocol reported locked, but the captured framebuffer still
showed the earlier desktop. A separate diagnostic confirmed DPMS stayed off
until ordinary Shift input; the runner now wakes graphical input before
selecting its keymap. See the [wake evidence](assets/usable-alpha/candidate7231-wake-README.md)
and [input-readiness evidence](assets/usable-alpha/candidate7231-keymap-README.md).
The original run remains failed; no full daily, screenshot, update or reboot
acceptance is claimed for this candidate.
[Partial evidence and exact revisions](assets/usable-alpha/candidate7231-README.md).

A subsequent candidate also includes the installer VT palette and dark ReGreet
preference. Those changes have Nix evaluation and override checks, but still
require a fresh image and visible installed-VM verification.

## Corrected provider runtime on the existing disk

On the same installed `7231d4b` disposable disk, a temporary user-service
`ExecStart` override loaded session `2e85655df116851781b79fc80403381eedef99c3`:
`/nix/store/6h6xv9jwvirbhgkxsjh7v3qamgcq61v5-sleepy-session-0.1.0`.
It was built from public root `d3252c67f09618414ca2d33aeb776e75246c3f26`
(491 release tests passed, two existing tests ignored), transferred through the
existing signed cache, and verified without changing its public key or trust
requirements.

The [actual doctor JSON](assets/usable-alpha/candidate7231-session2e85655-doctor.json)
reports `ok: true`, audio available with the VM's virtual audio device, Bluetooth
unavailable, and battery unsupported. The captured UPower 1.91.3 absence
response now classifies correctly. Screenshot helper remains unavailable;
this report does not prove the separate shell screenshot workflow. It is a
summary of daemon capabilities, not proof that every operation succeeds.

This was a diagnostic runtime override on an older installed image, with
additional locker diagnostic instrumentation active. It is **not** a fresh
installation of the corrected production graph, an update/rollback test, or
proof of a completed native-lock or screenshot roundtrip. The original failed
combined result remains unchanged. Only the doctor JSON was extracted from the
mixed diagnostic report; command echoes and locker debug messages were omitted.

## Fresh migration VM and dconf

Root `d3252c67f09618414ca2d33aeb776e75246c3f26` passed the isolated fresh
NixOS migration VM check in 44.01 seconds. Its assertions read the actual user's
dconf database and require `prefer-dark`, alongside the existing Home Manager
migration and rollback/state-preservation checks. The fixture explicitly enables
the dconf writer service needed by standalone Home Manager.

[Compact execution log](assets/usable-alpha/d3252c-dconf-migration.log) and
[exact result/source provenance](assets/usable-alpha/d3252c-dconf-migration.json)
are preserved. Reproduce with
`nix build github:sleepylinux/sleepy/d3252c67f09618414ca2d33aeb776e75246c3f26#checks.x86_64-linux.update-safety-vm --max-jobs 1 -L`.
This is a migration fixture VM, not the final installed-desktop acceptance.
