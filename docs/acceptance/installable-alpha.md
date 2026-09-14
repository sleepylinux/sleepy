# Installable Sleepy alpha acceptance

## Candidate and scope

This is an x86_64 UEFI network installer with a console TUI, a 512 MiB ESP and
compressed Btrfs root. It includes no live desktop. NVIDIA, gaming, development,
Flatpak and Bluetooth are opt-in. Acceptance below distinguishes installed-disk runs from build checks. A final
image with the additional locker fixes is undergoing validation.

The initial end-to-end installed-disk run passed at root
`40632d4286be6c39e5a133a598c3efdb62f1f1b9`, using a separately signed local binary
cache with signature verification enabled. A second full run at
`c6f95ef872fe19ea5577d59eda2552af305e2471` passed using public sources and public
substituters only, without a local cache override. The additional-keyboard/locker
run found defects described below; the final candidate must repeat that gate.

## Verified behavior

The first complete run (`work/vm-alpha-7/result.json`) used QEMU 11.1.0/KVM,
OVMF, four vCPUs, 8 GiB RAM, plain virtio-vga and a newly created 40 GiB disk.
It performed the actual visible TUI installation, shut down, detached the ISO,
and booted the installed disk. No installed test PAM, autologin or injected user
account was used. It passed:

- Real password authentication in ReGreet and a console, plus passworded sudo.
- UWSM/Hyprland startup, the Sleepy shell/session socket and real terminal/file
  manager windows.
- First-login welcome completion and its persistent suppression after reboot.
- Shell and session daemon recovery after actual SIGKILL.
- A changed Hyprland setting and user state surviving two subsequent boots.
- An invalid update leaving the active system, profile and boot entries intact.
- Building and booting a second generation, selecting the original generation,
  then booting it and authenticating with the network disconnected.
- Refusing an invalid install target and an offline install without disk writes;
  SIGTERM after formatting/mounting cleaned up mounts and released the lock.

A separate fresh production VM found and then verified the fix for logout with
an open first-login welcome. The successful run took 77.52 seconds. It kept the
welcome open, verified no pending start job, stopped the UWSM session, checked all
managed services stopped and returned to ReGreet. Its existing test-only PAM is
not evidence of password authentication; that is covered by the installed-disk
runs above.

The public-source run (`work/vm-alpha-8/result.json`) repeated the complete path
and clean final shutdown: 23 recorded stages passed. Its image SHA-256 is
`8d7c4e9a53eb8ef3c5fd9a72bdb46a939d1cf08d6d444852d6386a56d70f2744`;
runner revision was `0df3a163e4efc23b4a91f5f1e3fd2482826f5d63` with a clean tree.

The subsequent RU run found that restarting the session daemon deleted the
independent locker socket. A demand-driven runtime owner now preserves both
clients’ sockets until they stop. Fresh production VM checks verified the same
locker PID and socket inode across daemon restarts and SIGKILL, and directory
cleanup after logout (87.09 seconds); the update-safety VM also passed (49.36
seconds). A real-password diagnostic then exposed a separate obsolete QML
unlock call. Its correction and the complete lock roundtrip are still pending.

## Build and regression checks

All 25 root flake checks passed at `f3866fc` before the runtime ownership fix. Unchanged check
outputs were reused from the Nix store; this is separate from the fresh boots.
Installer/backend tests cover identity/occupancy checks, secret handling,
cleanup, default-disabled options, generated keyboard configuration and real
80×24 dialog interaction. The private Nix Git dependency has a red-to-green
fetchGit/fetchTree test with no Git in the caller PATH. SDK UTF-8 validation and
the real-child session regression have their own component PR checks.

## Limits and next work

The tested hardware is disposable QEMU hardware. Physical AMD/Intel/NVIDIA,
hybrid graphics, Wi-Fi radios, suspend and gaming are not accepted by these
runs. Optional profiles were evaluated, not exercised on physical hardware.
Encryption, Secure Boot and a fully offline installation are not implemented.
The installer UI is English; additional desktop layouts retain US for password
entry and use Alt+Shift. Recovery consoles remain US.

The alpha has saved source, local generations and rollback, but no promoted
update channels or published release cache. Build-time source compilation may
make a public-source installation slower than a cached one. Use the documented
40 GiB/8 GiB VM configuration. No protected permanent VM or installed host OS was
modified. PRs remain drafts; no merge or release was performed.

The next product priority is a read-only `sleepyctl doctor` built on the existing
v3 desktop capability stream, followed by the physical hardware matrix.

Reproduction commands and keyboard behavior are in the
[installation runbook](../runbooks/installable-alpha.md); retained-generation
and installation-media recovery are in [recovery](../recovery.md).
