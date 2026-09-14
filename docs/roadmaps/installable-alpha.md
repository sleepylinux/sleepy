# Installable alpha working plan

Scope: x86_64 UEFI, minimal network installation media, a keyboard-accessible
Sleepy TUI, GPT / 512 MiB ESP / Btrfs, real user credentials. No live desktop.
Additional drivers, gaming, development and Flatpak are opt-in. Encryption follows
the verified unencrypted path. Never operate on the development host's disks.

- [ ] Restore component build reliability; preserve locked source revisions.
- [ ] Integrate a small `dialog` frontend and a structured Python backend using
  the existing NixOS installation tools. Validate disk identity and occupancy at
  the destructive boundary; keep passwords out of arguments, logs and the store.
- [ ] Build and boot installer media, install to a disposable UEFI VM disk,
  detach media, boot installed disk, authenticate and exercise desktop/reboots.
- [ ] Verify refusal/error paths, session recovery and previous generations.
- [ ] Record actual evidence and reproduction commands; prepare draft changes.

Initial state: root f09d320, last CI 33927986599 failed in sleepy-session's child
startup test. QEMU/KVM and OVMF available; Nix absent. Docker is available, so
build tools and their store will live in a dedicated container/volume.

Design: reuse ncurses `dialog`, util-linux, filesystem tools and `nixos-install`
instead of introducing a graphical installer or a second provisioning framework.
The media carries the pinned source; target packages require network access.
The installer never promises to restore data after disk erasure. The installed
system retains its configuration and boot generations for recovery.
