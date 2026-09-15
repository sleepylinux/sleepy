# Usable alpha validation in progress

This record covers the daily-usability candidate. It does not replace the
[accepted installer ISO](installable-alpha.md) until a complete installed-disk
run passes for the new production graph.

## Implemented and targeted checks

- Conservative absent-hardware providers: session `004e81d`, component CI
  [34911942420](https://github.com/sleepylinux/sleepy-session/actions/runs/34911942420)
  passed. New virtual-audio and absent-device VM acceptance is pending.
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
showed the earlier desktop. The cause is under investigation; no full daily,
screenshot, update or reboot acceptance is claimed for this candidate.
[Partial evidence and exact revisions](assets/usable-alpha/candidate7231-README.md).

A subsequent candidate also includes the installer VT palette and dark ReGreet
preference. Those changes have Nix evaluation and override checks, but still
require a fresh image and visible installed-VM verification.
