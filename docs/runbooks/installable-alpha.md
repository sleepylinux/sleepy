# TUI installation alpha

The installer is a network installation image for x86_64 UEFI machines. It uses
`dialog` in a console, with no live desktop. The whole selected disk is erased:
GPT, a 512 MiB FAT32 EFI partition, and a compressed Btrfs root. The validated VM
configuration uses a 40 GiB disk and 6 GiB RAM. Use that configuration for alpha
testing; smaller systems are not validated.
The verified snapshot below is unencrypted. This development branch adds optional
LUKS2; its actual encrypted VM acceptance is still pending.

Build the verified source with Nix and flakes enabled:

```sh
nix build github:sleepylinux/sleepy/86240920109f37263c3260ea501c2a15fafa7dd8#installer-iso \
  --max-jobs 1 --cores 2 --out-link result-installer
sha256sum result-installer/iso/*.iso
```

The [current acceptance record](../acceptance/usable-alpha.md) records the
821 MiB artifact, checksum, pins and clean runner. It passed 44 gates including
fresh installation, candidate boot and offline rollback. Separate source `7c75fa8`
passed 40 offline boot-repair gates; its recovery implementation is unchanged.
Images predating the mounted-descendant target validation fix are superseded.
This is a tested local alpha artifact, not a published release.

The final run used a separately supplied signed dependency cache. The earlier
`229a794` diagnostic also completed a public-only install and password desktop
login, then failed its recovery gate. Public-only installation can build
uncached components; allow substantially more time than the cached measurement.

To reuse the retained signed cache, serve it on loopback:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 \
  --directory work/artifacts/sleepy-cache-97830de
```

Use runner `d40861dddf01018b4de7bb13a81012de57f23625` or a reviewed successor:

```sh
python3 scripts/vm/installable-alpha.py \
  --iso work/artifacts/sleepy-usable-8624092.iso \
  --image-source-revision 86240920109f37263c3260ea501c2a15fafa7dd8 \
  --output work/fresh-acceptance --memory 6144 \
  --keyboard ru --interrupt-install --daily-usability \
  --candidate-revision d40861dddf01018b4de7bb13a81012de57f23625 \
  --candidate-nar-hash sha256-vTdwqyzrnTo0PihpWPUGu5ZSH+mVNU4HnKz82jl7qe0= \
  --cache-url http://10.0.2.2:8080 \
  --cache-public-key "$(cat work/artifacts/sleepy-cache-97830de/public-key)"
```

Omit both cache arguments to use public sources only. The cache contains signed
component/dependency closures, not the old installer or a complete offline
system. Public network access remains necessary for installation. Its
`verification.json` records the original 1177 signatures and later component
extensions; no private signing key is distributed. The runner requires QEMU/OVMF, Python pexpect/Pillow and Tesseract;
use `--help` for firmware paths. Choose a new output directory for its disposable
disk. To test guided boot repair instead, omit both candidate arguments and add
`--boot-recovery`. Candidate updates, `--boot-recovery` and `--update-safety` are
separate, incompatible scenarios. The candidate above is a tested source, not a
published update channel.

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

## Optional encryption in the development branch

After the software checklist, **Protect your files** offers encryption, off by
default. Enabling it asks twice for a separate disk passphrase. Use 12–128
printable ASCII characters; spaces are allowed. Installer, initrd and recovery
use US keys. The passphrase unlocks the disk at every boot; the account password
is still required for desktop login. The EFI partition remains unencrypted.

The final erasure confirmation shows whether encryption is selected. Passwords
are transported to the backend through stdin and are absent from command
arguments, diagnostics and the generated configuration. Boot repair still
requires the disk passphrase; it cannot reset or bypass it.

To validate a newly built image from this branch, use a fresh output directory
and add `--encrypt-install --boot-recovery` to the runner, omitting candidate and
update-safety arguments. The runner creates a separate private test credential,
checks wrong-passphrase rejection, and exercises offline repair without changing
partition contents during inspection. Its unit tests and Nix configuration checks
pass; **the real encrypted VM run has not passed yet**. See [recovery](../recovery.md).

## Everyday desktop in the accepted snapshot

The current image verifies the default desktop workflows below. Optional
Flatpak and development acceptance belongs to the historical `97830de` run;
the acceptance record keeps those scopes separate.

Open a terminal with `Super+Return`, or the application launcher with `Super+D`.

- Run `sleepy-system` (or `sleepy-system menu`) for system status and recovery.
  `sleepy-system status` prints the current running system, the system booted
  this session and the selected system profile; they can differ after a switch.
  `sleepy-system generations` lists recovery generations. Both are read-only.
  The menu asks for confirmation before applying saved settings or rolling back;
  Escape cancels the main menu. Direct `rebuild` and `rollback` commands start
  the requested operation without that menu confirmation and may ask for your
  administrator password in the terminal.
- `sleepy-system rebuild` applies saved settings using the running generation's
  retained source. It may download or build dependencies and restart services; it does not select a new Sleepy
  release or advance a channel. The separate [approved update](../updates.md)
  action selects a reviewed immutable source for the next boot. Rollback switches
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
clipboard result. The accepted snapshot includes real saved-image and clipboard
PNG checks; the absent SDK helper remains a separate limitation.

## VM gate details

The command above creates a new disk and firmware variables, uses KVM when
accessible and otherwise TCG, drives the visible TUI, and detaches the ISO for
each installed-disk boot. It authenticates normally with the created password.
The candidate command boots the installed base, the prepared candidate, then
the rolled-back base offline. It tests rejected updates, actual builder
interruption, retained rebuild source and subsequent validation after rollback.

With `--boot-recovery` instead of the candidate arguments, the runner removes
boot-entry configuration only on that disposable disk, proves
the no-entry boot, reconnects the ISO, tests mounted-target rejection and
read-only inspection/cancel, then repairs through the visible TUI. The repaired
disk boots offline and must retain its profile, configuration and user state.

Daily checks exercise applications, actual PNG capture, keyring, settings,
first-boot completion, lock/VT/layout/input wake and shell/session restart. Omit
`--keyboard ru` to exercise the default US-only installation. Optional
`--pause-at-greeter` releases QMP for manual inspection before entering the
password; ordinary automated runs do not require that pause.

The historical update scenario instead used `--update-safety --flatpak-recovery`:
it rejected an invalid configuration, built and booted a development generation,
then selected and booted the previous generation offline. Its exact 978 image,
47 gates and three disk boots remain separately recorded; do not claim that
this covers every failed activation or repeat it with a superseded installer.

Results, screenshots and logs remain in the private output directory. The
random test password is stored only in mode-0600 `test-credential`; never publish
that file or the virtual disk. `result.json` preserves failures and completed
substeps. A build or syntax check is not evidence of a fresh VM boot.
