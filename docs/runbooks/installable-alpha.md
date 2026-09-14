# TUI installation alpha

The installer is a network installation image for x86_64 UEFI machines. It uses
`dialog` in a console, with no live desktop. The whole selected disk is erased:
GPT, a 512 MiB FAT32 EFI partition, and a compressed Btrfs root. The minimum disk
size is 16 GiB; use 40 GiB for development VMs. Encryption is not implemented.

Build the pinned source with Nix and flakes enabled:

```sh
nix flake check --no-build
nix build .#installer-iso --out-link result-installer
ls -lh result-installer/iso/
sha256sum result-installer/iso/*.iso
```

Boot the ISO in a UEFI VM with a new disposable disk. Secure Boot is not supported
by this alpha. Connect Ethernet, or choose Network in the TUI to configure Wi-Fi.
Choose Install, identify the target disk, enter account and regional settings,
and select optional software. NVIDIA (Turing or newer), gaming, development,
Flatpak and Bluetooth are all unchecked by default. NVIDIA and Steam require
accepting their upstream licenses through the selected configuration.

Review the disk identity and type its complete device path to confirm erasure.
Wait for completion, shut down, detach the ISO, then boot the disk. Sign in with
the account and password created in the installer. The first desktop login shows
keyboard shortcuts and recovery commands.

The backend checks connectivity and evaluates the requested NixOS configuration
before erasing. Later package downloads can still fail. An interrupted installation
can leave a partially installed disk; retrying erases it again. There is no recovery
of erased files. Diagnostics are in `/var/log/sleepy-installer.log` on the image;
copy them before shutting down. Passwords are not written there.

The installed configuration is `/etc/nixos/flake.nix`, with the pinned Sleepy
source in `/etc/nixos/sleepy-source`. `sleepy-system rebuild` reapplies that saved
configuration; it does not promote an untested upstream channel automatically.
`sleepy-system generations` lists recovery points and `sleepy-system rollback`
activates the previous system generation. See [recovery](../recovery.md).

## Reproduce the real VM gate

Requires QEMU, OVMF, Python with pexpect and Pillow, and Tesseract. Firmware paths
vary by distribution; override `--firmware` and `--vars` as needed.

```sh
python3 scripts/vm/installable-alpha.py \
  --iso "$PWD/result-installer/iso/sleepy-0.1.0-alpha-x86_64-linux.iso" \
  --output "$PWD/work/vm-alpha-run-1" --pause-at-greeter
```

The output directory must not exist. The runner creates its own disk and firmware
variables, uses KVM when accessible and otherwise TCG, drives the actual visible
TUI, and detaches the ISO before disk boot. `--pause-at-greeter` is an inspection
gate for the first run; its printed instructions allow the engineer to select
the account and verify the password field before credentials are entered.

Results, screenshots and logs remain in the private output directory. A random
test password is stored only in its mode-0600 `test-credential` file; do not publish
that file or the virtual disk. `result.json` distinguishes completed stages from
failures. A build or a successful runner syntax check is not evidence of a VM boot.

For repeated local validation, the runner accepts `--cache-url` and
`--cache-public-key` for a separately signed local binary cache. This changes only
the disposable image's running Nix daemon configuration, retains signature checks,
and avoids downloading already built components again. It is not a release cache.

Status: implementation and configuration checks completed; fresh installed-disk
acceptance remains pending until the real VM evidence is recorded.
