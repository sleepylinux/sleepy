# Sleepy Linux

Sleepy Linux is an experimental NixOS desktop with a VM-verified TUI installer.
Its primary session is a UWSM-managed
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

- [TUI installation and VM validation](docs/runbooks/installable-alpha.md);
- [installable alpha evidence and limitations](docs/acceptance/installable-alpha.md);
- [runtime ownership and failure semantics](docs/architecture/shell-runtime-integrations.md);
- [real VM runbook](docs/runbooks/sleepy-vm-hyprland.md);
- [acceptance record](docs/acceptance/hyprland-sleepy-desktop.md);
- [active MVP roadmap and next-agent handoff](docs/roadmaps/installable-alpha.md);
- [verified daily desktop snapshot and remaining limits](docs/acceptance/usable-alpha.md).

Sleepy Linux is licensed under `GPL-3.0-only`; see [LICENSE](LICENSE).
