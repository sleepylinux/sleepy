# Recovering the Sleepy desktop

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
