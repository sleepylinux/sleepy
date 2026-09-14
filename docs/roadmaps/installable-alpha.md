# Installable alpha working plan

Scope: x86_64 UEFI, minimal network installation media, a keyboard-accessible
Sleepy TUI, GPT / 512 MiB ESP / Btrfs, real user credentials. No live desktop.
Additional drivers, gaming, development and Flatpak are opt-in. Encryption follows
the verified unencrypted path. Never operate on the development host's disks.

- [x] Restore component build reliability; preserve locked source revisions.
- [x] Integrate a small `dialog` frontend and a structured Python backend using
  the existing NixOS installation tools. Validate disk identity and occupancy at
  the destructive boundary; keep passwords out of arguments, logs and the store.
- [x] Build and boot installer media, install to a disposable UEFI VM disk,
  detach media, boot installed disk, authenticate and exercise desktop/reboots.
- [x] Verify refusal/error paths, session recovery and previous generations.
- [x] Record actual evidence and reproduction commands; prepare draft changes.

Initial state: root f09d320, last CI 33927986599 failed in sleepy-session's child
startup test. QEMU/KVM and OVMF available; Nix absent. Docker is available, so
build tools and their store will live in a dedicated container/volume.

Design: reuse ncurses `dialog`, util-linux, filesystem tools and `nixos-install`
instead of introducing a graphical installer or a second provisioning framework.
The media carries the pinned source; target packages require network access.
The installer never promises to restore data after disk erasure. The installed
system retains its configuration and boot generations for recovery.

Next increment: read-only desktop diagnostics and cleanup.

- [x] Remove obsolete VM disks, intermediate images, build outputs and Nix cache.
- [x] Implement bounded, privacy-preserving `sleepyctl doctor`; review and unit test.
- [x] Verify the Nix package in the installed disposable VM, including offline and daemon recovery.
- [x] Integrate reviewed pins and remove the remaining temporary VM/build files.

Merge gate: exact-head CI and independent review for session PR #10 and root
PR #9. Installer/root PR #8 and its three component PRs are merged.
Next product priority: audio/battery parse errors and Bluetooth timeout reported
by doctor; then physical hardware profiles and suspend acceptance.
