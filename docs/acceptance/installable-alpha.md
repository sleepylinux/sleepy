# Installable Sleepy alpha acceptance

## Accepted artifact

The x86_64 UEFI TUI installation path passed on a newly created disposable VM
disk at root **`9bca73cdc125bbf7704e8038dc46cc383cd36fd3`**. This is a network
installer without a live desktop. NVIDIA, gaming, development, Flatpak and
Bluetooth are unchecked options. Layout: GPT, 512 MiB FAT32 ESP, compressed
Btrfs root. Encryption is not implemented.

Artifact: `sleepy-alpha-9bca73c.iso`, **856,686,592 bytes (817 MiB)**.
SHA-256: `343afd66349ad64406784be1ee861d74e0888973781bdea37d2cc13e66231e41`.
The [artifact manifest](assets/installable-alpha/current-run/artifact-manifest.json)
records the source tree, generated lock hash and all component revisions.
The local artifact and checksum file are under `work/artifacts/`; no release
has been published.

## Actual installed-disk verification

[VM11 result](assets/installable-alpha/current-run/result.json): **25 recorded
stages passed**. Image and runner used the exact revision above with a clean
tree. QEMU 11.1.0/KVM, OVMF, four vCPUs, 8 GiB RAM, ordinary virtio-vga and a new
40 GiB virtual disk were used. The runner drove the visible TUI, selected US+RU,
shut down, detached the ISO and booted the installed disk. No installed test PAM,
autologin, injected account or replacement locker executable was used.

The installation used a separately signed local binary cache with signature
verification enabled. This override affected only the running installation
media; the installed system retained its normal substituters. A separate
[public-source run](assets/installable-alpha/public-source-run/result.json)
at `c6f95ef872fe19ea5577d59eda2552af305e2471` passed the complete installation,
update and rollback path with no local cache override. It predates the final
keyboard/locker fixes and is recorded separately, not as current-image proof.

The current run verified:

- Invalid target and offline-install rejection without disk writes; actual
  SIGTERM after formatting/mounting, followed by unmounting and lock release.
- Real password login through ReGreet/PAM, console login and passworded sudo.
- UWSM/Hyprland, shell/session sockets and real Ghostty/Thunar windows.
- First-login welcome completion and its suppression after subsequent boots.
- SIGKILL recovery of both shell and session daemon; a working independent
  locker afterwards, with native password authentication and RU → US switching.
- An actual Hyprland setting and user state surviving both subsequent boots.
- A rejected update preserving the current system, profile and boot entries.
- Building and booting generation 2, selecting generation 1, then booting it
  with the NIC disconnected and authenticating again.
- Native lock/unlock on all three disk boots, fixture restoration and a clean
  final shutdown.

Compact guest reports are retained for the
[first disk boot](assets/installable-alpha/current-run/installed-guest-report.txt),
[second generation](assets/installable-alpha/current-run/generation2-guest-report.txt)
and [offline rollback](assets/installable-alpha/current-run/offline-reboot-guest-report.txt).
Screenshots show the [optional TUI choices](assets/installable-alpha/current-run/installer-options.png),
[disk confirmation](assets/installable-alpha/current-run/installer-confirmation.png),
[locker](assets/installable-alpha/current-run/installed-locked.png) and
[unlocked desktop](assets/installable-alpha/current-run/installed-unlocked.png).
[Evidence checksums](assets/installable-alpha/SHA256SUMS) cover the saved files.
Passwords, virtual disks and the private cache signing key are excluded.

## Build and regression checks

All [25 root flake checks](assets/installable-alpha/current-run/flake-check-result.json)
passed at the accepted revision. Changed production and migration/update-safety
VMs ran freshly in 88.81 and 44.56 seconds respectively; unchanged derivations
were reused. Those NixOS VM tests retain their existing test authentication and
are separate from the real-password installed-disk proof above.

Installer tests cover disk identity/occupancy, secret handling, interruption,
opt-in defaults, generated keyboard configuration and real 80×24 dialog input.
The private Nix Git dependency has a red-to-green fetchGit/fetchTree regression
with no Git in the caller PATH. SDK UTF-8 parsing, session child startup and
post-dispatch timeouts, and native locker authentication have component
regressions. [Component CI](assets/installable-alpha/current-run/component-ci.json)
is green for the exact SDK/session/desktop pins. The complete
[root CI run](https://github.com/sleepylinux/sleepy/actions/runs/34901792384)
also passed at the accepted revision, including fresh-clone reproducibility,
all checks and both NixOS/Home Manager builds; its
[result metadata](assets/installable-alpha/current-run/root-ci.json) is retained.

Earlier fresh VMs reproduced and verified fixes for logout with an open welcome
and deletion of the independent locker socket during a session restart. A
separate real-password clone verified the native unlock correction. Thunar
rendered a real file; its initially empty HOME view contained only hidden
entries, which Ctrl+H displayed correctly. These diagnostics did not modify the
accepted image or a permanent host OS.

## Limits and next work

Only disposable QEMU hardware is accepted. Physical AMD/Intel/NVIDIA, hybrid
graphics, Wi-Fi radios, suspend, controllers and gaming remain unverified.
Optional profiles were evaluated; they were not exercised on physical hardware.
Secure Boot, encryption, a fully offline installer, promoted update channels
and a published release cache are not implemented. The TUI is English; US stays
available alongside selected desktop layouts through Alt+Shift, and recovery
consoles always use US. Source compilation can make installation take longer.

The next product priority is read-only `sleepyctl doctor` using existing desktop
capability diagnostics, followed by the physical hardware matrix. PRs remain
drafts: no merge, public release or permanent host installation was performed.

See the [installation runbook](../runbooks/installable-alpha.md) for reproduction
and [recovery](../recovery.md) for generations and installation-media recovery.
