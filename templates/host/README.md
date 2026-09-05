# Personal Sleepy host

Generate `hardware-configuration.nix` on the target machine; it is deliberately
not included here. Edit `configuration.nix` for your username, location, boot
loader and GPU. If renaming the flake's `nixosConfigurations.sleepy`, also update
`/etc/snug/system.json`'s `host` value. Keep this directory at `/etc/nixos`, owned
by root and not group/world writable. Use `sudoedit` to customize it.

See [the installation guide](https://github.com/sleepylinux/sleepy/blob/main/docs/installation.md)
for installation, normal-user password setup, NVIDIA configuration and recovery.
The first `nix flake lock` pins Sleepy and its dependency graph. Retain that lock.
