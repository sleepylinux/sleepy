# TUI installation alpha

The installer is a network installation image for x86_64 UEFI machines. It uses
`dialog` in a console, with no live desktop. The whole selected disk is erased:
GPT, a 512 MiB FAT32 EFI partition, and a compressed Btrfs root. The validated VM
configuration uses a 40 GiB disk and 8 GiB RAM. Use that configuration for alpha
testing; smaller systems are not validated.
Encryption is not implemented.

Build the pinned source with Nix and flakes enabled:

```sh
nix flake check --no-build
nix build .#installer-iso --out-link result-installer
ls -lh result-installer/iso/
sha256sum result-installer/iso/*.iso
```

To reproduce the accepted artifact from its public source revision:

```sh
nix build github:sleepylinux/sleepy/97830de29099483356a7cff1a28751edfcc538d9#installer-iso \
  --out-link result-installer
```

The [current accepted snapshot](../acceptance/usable-alpha.md) records its SHA256,
component graph and clean runner revision. A later checkout may produce a
different artifact checksum. This is a tested alpha snapshot, not a published
release. Its full VM run used a separately supplied signed local binary cache;
a public-cache-only installation has not been validated.

Boot the ISO in a UEFI VM with a new disposable disk. Secure Boot is not supported
by this alpha. Connect Ethernet, or choose Network in the TUI to configure Wi-Fi.
Choose Install, identify the target disk, enter account and regional settings,
and select optional software. NVIDIA (Turing or newer), gaming, development,
Flatpak and Bluetooth are all unchecked by default. NVIDIA and Steam require
accepting their upstream licenses through the selected configuration. Use Space
to toggle an option and Enter to continue. Leaving every option unchecked is a
supported minimal desktop installation.

The installer and recovery consoles use US keys. Selecting Russian, German or
Czech adds that desktop layout alongside US; Alt+Shift switches between them.
US remains first so the password entered during installation stays usable.

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

## Everyday desktop in the current candidate

The following additions are implemented in the usability branch; the immutable
`9bca73c` ISO above predates them. Combined installed-VM acceptance is pending.

Open a terminal with `Super+Return`, or the application launcher with `Super+D`.

- Run `sleepy-system` (or `sleepy-system menu`) for system status and recovery.
  `sleepy-system status` prints the current running system, the system booted
  this session and the selected system profile; they can differ after a switch.
  `sleepy-system generations` lists recovery generations. Both are read-only.
  The menu asks for confirmation before applying saved settings or rolling back;
  Escape cancels the main menu. Direct `rebuild` and `rollback` commands start
  the requested operation without that menu confirmation and may ask for your
  administrator password in the terminal.
- `sleepy-system rebuild` applies `/etc/nixos#installed`. It may download or
  build dependencies and restart services; it does not select a new Sleepy
  release, advance a channel or update the saved source pin. Rollback switches
  to the previous system generation; it does not restore personal files or
  application data. Progress and the diagnostic log path appear in the terminal.
  Logs use `$XDG_STATE_HOME/sleepy/system`, normally
  `~/.local/state/sleepy/system`, with private file permissions. See
  [recovery](../recovery.md) for boot-menu recovery.
- Press `Print`, then drag and release to select a screen region. Swappy opens
  the captured image for annotation; press `Ctrl+S` to save a PNG. The default
  is `Sleepy-YYYYMMDD-HHMMSS.png` in `~/Pictures/Screenshots`; a configured XDG
  Pictures directory or host `save_dir` override changes the destination.
  Escape cancels the picker. `Shift+Print` copies the selected region directly
  as a PNG; paste into an application that accepts images. Swappy's
  [keyboard reference](https://github.com/jtheoof/swappy/blob/v1.8.0/README.md#keyboard-shortcuts)
  lists its editor controls.
- Open a saved PNG in Thunar to use imv, the default image viewer; `q` closes
  it. Host profiles can override the viewer and MIME defaults.
- Run `fastfetch` for system information and the Sleepy crescent. It does not
  run automatically when a terminal opens. GTK theme, terminal, launcher and
  Fastfetch defaults remain overridable through the Home Manager configuration.
- If Flatpak was selected during installation, open Software from the launcher.
  Flathub registration is scheduled shortly after boot; after a failed attempt,
  it retries about five minutes later without holding up login. Reconnect the
  network and allow time for the retry. `flatpak remotes --system` lists the
  registered sources; `systemctl status sleepy-flathub.service` shows setup
  status. An empty catalog while offline does not mean registration succeeded.
  Without the optional profile, Software and this Flathub timer are not enabled.

The shell's Print/Shift+Print picker is separate from the SDK screenshot
capability: `sleepyctl doctor` can report optional screenshot support as
unavailable when `sleepy-capture-helper` is absent. That status describes the
[daemon helper path](https://github.com/sleepylinux/sleepy-session/blob/004e81dbfd10ebcec569129aa9eb6ae1559dab5f/src/desktop/utilities.rs),
not a test of the [native shell picker](../architecture/shell-runtime-integrations.md).
Neither status alone proves a successful capture; check the saved image or
clipboard result. These instructions describe implemented behavior, not a
successful combined VM acceptance run.

## Reproduce the real VM gate

Requires QEMU, OVMF, Python with pexpect and Pillow, and Tesseract. Firmware paths
vary by distribution; override `--firmware` and `--vars` as needed.

```sh
python3 scripts/vm/installable-alpha.py \
  --iso "$PWD/result-installer/iso/sleepy-0.1.0-alpha-x86_64-linux.iso" \
  --output "$PWD/work/vm-alpha-run-1" \
  --image-source-revision "$(git rev-parse HEAD)" \
  --interrupt-install --update-safety --keyboard ru --pause-at-greeter
```

The output directory must not exist. The runner creates its own disk and firmware
variables, uses KVM when accessible and otherwise TCG, drives the actual visible
TUI, and detaches the ISO before disk boot. `--pause-at-greeter` is an inspection
gate for the first run; inspect the default UWSM session, press Enter to select
the account, and verify the password field before allowing credentials to be
entered. The update gate deliberately rejects an invalid configuration, builds
a second generation, boots it, selects the original generation, and boots that
generation with the virtual network disconnected. It also checks real password
authentication, applications, first-boot completion, persistent settings and
recovery after killing the shell and session daemon. The selected keyboard is
checked in Hyprland, followed by a real Sleepy locker password roundtrip; with
an additional layout selected, the test switches back to US on the lock screen.
Omit `--keyboard ru` to exercise the default US-only installation.

Results, screenshots and logs remain in the private output directory. A random
test password is stored only in its mode-0600 `test-credential` file; do not publish
that file or the virtual disk. `result.json` distinguishes completed stages from
failures. A build or a successful runner syntax check is not evidence of a VM boot.

For repeated local validation, the runner accepts `--cache-url` and
`--cache-public-key` for a separately signed local binary cache. This changes only
the disposable image's running Nix daemon configuration, retains signature checks,
and avoids downloading already built components again. It is not a release cache.

Status: the complete installed-disk gate passed at
`9bca73cdc125bbf7704e8038dc46cc383cd36fd3`, including native password lock/unlock
and offline rollback. See the [acceptance record](../acceptance/installable-alpha.md)
for the ISO checksum, exact revisions, screenshots and remaining limitations.
