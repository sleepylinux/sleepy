# Sleepy Linux

Sleepy Linux is a pre-alpha NixOS desktop. Its primary session is a UWSM-managed
Hyprland session with a modular Quickshell desktop installed by
`sleepy-desktop`, typed session services from `sleepy-session`, shared schemas
from `sleepy-sdk`, and immutable artwork from `sleepy-artwork`.

The shell preserves the complete Caelestia Shell v2.4.0 interaction and visual
surface graph while using Sleepy names, packages, state paths, IPC contracts,
and supervision. It does not download or execute Caelestia at runtime. Direct
desktop integrations such as Hyprland, NetworkManager, PipeWire, MPRIS,
StatusNotifierItem, UPower, brightness and VPN tools remain replaceable QML
providers; protected session transitions go through `sleepy-sessiond`.

Start with:

- [runtime ownership and failure semantics](docs/architecture/shell-runtime-integrations.md);
- [real VM runbook](docs/runbooks/sleepy-vm-hyprland.md);
- [acceptance record](docs/acceptance/hyprland-sleepy-desktop.md);
- [full-parity implementation plan](docs/superpowers/plans/2026-09-01-caelestia-v2.4.0-full-parity.md).

## Install and use

Build the minimal live ISO with `nix build .#iso`. It boots into a terminal
installer with package categories, hardware detection and an explicit disk
confirmation. The initial image targets x86_64 UEFI and legacy BIOS PCs and
requires internet access to install the desktop and selected packages.
See [installation and hardware setup](docs/installation.md).

Snug handles packages, temporary tools, project environments and rolling updates:

```sh
snug -i vim                     # permanent personal package
snug -it git -- git --version    # one command with temporary tools
snug -d init python my-project   # locked development environment
snug -u                         # personal package updates
snug -u --system                # rolling Sleepy update (sudo authentication)
snug -b --system                # system-generation rollback
snug --help
```

Short flags have long equivalents, such as `--install --temporary`. Use
`snug nix …` for the complete underlying Nix interface. The permanent command
reference is [docs/snug.md](docs/snug.md), also installed in `share/doc/snug/`.
System-selected packages remain declarative in `/etc/nixos/configuration.nix`;
Snug's personal profile is separate from system and Home Manager packages.

The [usability audit](docs/audits/2026-09-05-usability.md) distinguishes implemented
features from outstanding VM and hardware acceptance. `sleepy-vm` contains
VM-specific disk UUIDs and is not a generic installation target.

Sleepy Linux is licensed under `GPL-3.0-only`; see [LICENSE](LICENSE).
