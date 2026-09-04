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

Sleepy Linux is licensed under `GPL-3.0-only`; see [LICENSE](LICENSE).
