# Recovering the Sleepy desktop

## Installed Hyprland alpha

Hold Space while booting to show systemd-boot and select a retained generation.
Generation numbers are local to each installation; inspect them with
`sleepy-system generations`. A new installation has no older generation until
its first successful system rebuild. Do not delete generations or run garbage
collection while investigating a failure.

If the desktop cannot start, press Ctrl+Alt+F2, log in with the account created
during installation. Recovery consoles use the same US keyboard as the installer,
including when an additional desktop layout was selected. Then run:


```sh
systemctl status greetd
systemctl --user status graphical-session.target sleepy-session.service sleepy-shell.service
journalctl --user -b -u sleepy-session.service -u sleepy-shell.service
sleepy-system generations
```

After correcting the cause of a shell failure, restart its managed unit:

```sh
systemctl --user reset-failed sleepy-shell.service
systemctl --user restart sleepy-shell.service
```

Use `sleepy-system rollback` to activate the previous generation, then reboot to
verify its boot path. This restores system packages and configuration, not user
documents, passwords, or erased disk contents. Keep independent backups.

## Guided boot-entry repair

The guided-recovery candidate adds this flow to the installation image. Its VM
acceptance is pending; the previously accepted `97830de` image still provides
the manual recovery terminal. Use the revision-bound acceptance record to
identify which image you have.

Boot the recovery-capable image in UEFI mode and choose **Recovery and
diagnostics**. Select the installed disk in **Recover Sleepy boot**. Sleepy
checks its identity and supported layout, mounts the Btrfs root read-only with
log replay disabled, and shows the current system and retained generations.
**Back** is selected by default; inspection does not start a repair.

Choose **Restore boot entries** and type the complete disk path shown in the
confirmation. This runs the selected installation's boot repair code as root;
use it only for your own trusted Sleepy installation. It writes boot files and
may update UEFI boot entries. It does not format partitions, download a new
system, select a different generation or restore erased personal files.

After **Boot repair complete**, shut down, remove the image, and boot the disk.
Hold Space to choose a retained generation. Repair uses the current retained
system profile; it cannot fix a missing Nix store or an invalid system
configuration. Diagnostics remain in `/var/log/sleepy-installer.log` on the
recovery image, so copy them before shutting down if needed.

Guided repair supports only the installer's original two-partition GPT layout:
first a FAT32 ESP, then Btrfs root. Mounted/busy, changed, encrypted, removable,
and unrecognized targets are rejected. A complete retained installation can be
repaired offline. Other layouts require manual diagnosis from **Leave installer**;
identify partitions with `lsblk -f` and never format them during recovery.
Do not run repair against the computer hosting a test VM.

## Historical Niri deployment record

The remaining sections document one earlier developer deployment. Its absolute
paths, generation numbers, and Niri commands do not describe new Hyprland installs.

## Boot a previous generation

At the systemd-boot menu, choose an older NixOS generation. The generation
immediately preceding the accepted deployment is generation 4:

```text
/nix/store/j2mkmzqv9zkxjp6s1ndn0ck49wwmv3cs-nixos-system-sleepy-26.05.8111.5880666fd9eb
```

The accepted deployment retained five generations. Do not delete generations
or run garbage collection while diagnosing a rollback.

If the graphical session is unavailable, switch to a TTY (normally
`Ctrl+Alt+F2` through `Ctrl+Alt+F6`), log in, and inspect the current and boot
profiles:

```bash
readlink -f /run/current-system
readlink -f /nix/var/nix/profiles/system
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

Roll the system profile back and activate it with:

```bash
sudo nixos-rebuild switch --rollback
```

Reboot only when needed to validate the boot path. Prefer a graceful reboot;
never force-reset a VM with unknown active user work.

## Inspect Niri and Quickshell

From the affected user session or an SSH login for that user:

```bash
systemctl --user --no-pager --full status \
  graphical-session.target niri.service quickshell.service
journalctl --user -b -u niri.service -u quickshell.service
systemctl --user show quickshell.service \
  -p ActiveState -p SubState -p Result -p NRestarts -p MainPID
```

The Quickshell unit allows three starts in 30 seconds, restarts on failure, and
waits two seconds between restarts. After diagnosing a start-limit failure,
clear only that failure state and start the managed unit:

```bash
systemctl --user reset-failed quickshell.service
systemctl --user start quickshell.service
systemctl --user show quickshell.service \
  -p ActiveState -p SubState -p Result -p NRestarts -p MainPID
```

Expected restored state is `active/running`, `Result=success`, and
`NRestarts=0`. Do not start an unmanaged Quickshell process alongside the Home
Manager service.

Niri logout is owned by the upstream session lifecycle. `Mod+Shift+E` opens
Niri's confirmation prompt; pressing Enter exits Niri. A correct logout stops
`graphical-session.target`, Quickshell, and the graphical polkit agent, then
greetd starts ReGreet again.

## Recover the adopted Niri configuration

The one-time adoption migration preserved the original regular file at:

```text
/home/lazy/.local/state/sleepy/migrations/20260823T183945Z.AXOPWZ/niri-config.kdl
```

Its recorded SHA-256 is:

```text
993aa205ed47eada18b0ed85a8d4c7b31480c56c9d182840121943dd286ad080
```

It remains owned by `lazy:users`; the migration directory is mode `0700` and
the backup is mode `0644`. Never print its contents. If Home Manager must be
rolled back and the original file restored:

1. Stop or log out of the graphical session.
2. Verify the backup hash and metadata.
3. Confirm `~/.config/niri/config.kdl` is the Sleepy-created managed symlink.
4. Move that symlink aside to a new, unused recovery name; do not overwrite it.
5. Move the verified backup back to `~/.config/niri/config.kdl`.

Stop if the target is a regular file, has an unexpected owner, or the hash does
not match. Do not use Home Manager `force = true` as a recovery shortcut.

## Recover the deployed source tree

`nixos-rebuild switch --rollback` uses the system profile and does not require
rewriting `/etc/sleepy`. If the source tree itself must be reverted, first
verify the intended retained copy, move the current tree to a new failure path,
and then move the retained copy into place. Never overwrite either retained
copy:

```text
/etc/sleepy.pre-d903c1-20260823T201338Z
/etc/sleepy.previous-20260823T183905Z
```

Run `checks/source-clean.sh` with tools from the lock before rebuilding from a
restored source tree.

## Host Super-key capture

If `Mod+T`, `Mod+Return`, `Mod+D`, or navigation works with direct guest input
but not from the virt-manager window, the host intercepted Super before Niri
received it. Grab the VM keyboard in virt-manager (use its configured grab-key
sequence) and retry. Diagnose a Niri binding only after distinguishing this
host-side capture behavior. The accepted binding tests used guest-directed
libvirt key events, so host interception was not part of their PASS result.
