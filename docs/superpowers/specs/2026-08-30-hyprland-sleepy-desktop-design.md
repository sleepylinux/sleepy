# Hyprland Sleepy Desktop Design

## Status and goal

Approved on 2026-08-30. This change replaces Niri and the current Sleepy
Quickshell UI with a branded Sleepy desktop based on the interaction model and
visual foundation of Caelestia Shell v2.4.0 and the Caelestia Hyprland dots.
ReGreet remains the login manager and Hyprland becomes the only production
compositor.

This is a source fork, not a packaged Caelestia installation. The product is
named Sleepy, its runtime paths and interfaces are owned by Sleepy, and
`sleepy-sessiond` is the authority for desktop state and system actions.
Caelestia remains an attributed GPLv3 upstream, not a runtime dependency or a
visible product identity.

The implementation spans `sleepy-sdk`, `sleepy-session`, `sleepy-desktop`, and
the root `sleepy` repository. Work uses the normal branch name
`feat/hyprland-sleepy-desktop` in each repository.

## Chosen approach

The project will import the released Caelestia Shell v2.4.0 source into
`sleepy-desktop`, rename the product boundary immediately, and replace the
upstream service layer with typed `sleepy-session` clients in vertical slices.
The branch is not complete merely because the imported shell renders: all
required services, compositor actions, tests, and VM acceptance must use the
Sleepy architecture before integration.

This was chosen over running the upstream shell unchanged because an unchanged
shell would bypass `sleepy-sessiond` and establish a second state authority.
It was also chosen over a visual reimplementation from scratch because a fork
preserves the requested behavior and animation quality while keeping the
backend boundary explicit.

## Ownership and naming

`sleepy-desktop` owns QML presentation, animations, layout, local transient UI
state, and the minimal native QML helpers needed only for rendering. It
produces the `sleepy-shell` executable and `sleepy-shell.service` user unit.

`sleepy-session` owns observed system state, persistence, policy, external
processes and D-Bus connections, Hyprland IPC, and all mutations. It continues
to produce `sleepy-sessiond` and `sleepyctl`.

`sleepy-sdk` owns strict versioned request, response, snapshot, event, error,
and capability documents shared between the daemon, CLI, and shell.

The root `sleepy` repository owns the NixOS and Home Manager composition,
Hyprland configuration, ReGreet integration, portals, runtime packages,
component pins, and VM acceptance.

The runtime must not create Caelestia-named processes, units, IPC endpoints,
configuration directories, or user-visible labels. Sleepy configuration and
state remain under the existing XDG `sleepy` directories. Source provenance,
copyright notices, and GPLv3 obligations are retained in license and `NOTICE`
files; attribution is never removed or rewritten as Sleepy authorship.

## Desktop and service boundary

The imported visual surfaces include the bar and taskbar, workspaces,
launcher, dashboard, sidebar, notification views, OSD, lock screen, session
menu, utilities, wallpaper and style views, overview-like window controls, and
per-monitor surfaces. Visual behavior should match the selected upstream
release unless Sleepy branding or the backend boundary requires a change.

QML must not run `nmcli`, `bluetoothctl`, `wpctl`, `playerctl`, `brightnessctl`,
`powerprofilesctl`, `upower`, `hyprctl`, or arbitrary shell commands. It sends
typed commands to `sleepy-sessiond` and renders daemon snapshots and events.
No user-controlled string is evaluated by a shell.

The service migration is divided as follows:

| Upstream responsibility | Sleepy owner |
| --- | --- |
| Audio devices, volume, mute, visualiser inputs | `sleepy-session` audio service |
| Network connections, Wi-Fi scans, VPN state | `sleepy-session` network service |
| Bluetooth adapter and device state | `sleepy-session` Bluetooth service |
| Brightness, battery, power profiles, night light | `sleepy-session` power/display services |
| MPRIS players, metadata and transport | `sleepy-session` media service |
| Notifications, history, DND and actions | existing `sleepy-session` notification authority |
| Launcher index, search and safe application launch | existing `sleepy-session` launcher authority |
| CPU, memory, disks, sensors and network usage | `sleepy-session` resources service |
| Weather and cached forecasts | existing `sleepy-session` weather provider |
| Wallpaper, colour scheme and theme persistence | `sleepy-session` theme/wallpaper service |
| Workspaces, windows, monitors and compositor actions | `sleepy-session` Hyprland adapter |
| Lock, suspend, logout, reboot and power off | `sleepy-session` session authority |
| Idle inhibition, recording and game mode | typed `sleepy-session` utility services |
| Presentation, animation and ephemeral open/closed state | `sleepy-desktop` only |

Capabilities remain independently degradable. Missing VM hardware, such as a
backlight, battery, or Bluetooth adapter, produces a typed unavailable or
unsupported state only for that capability; it must not prevent the desktop
from becoming ready.

The shell connects through private mode-0600 Unix sockets in
`$XDG_RUNTIME_DIR/sleepy`. A reconnect receives a complete snapshot before
incremental events. Requests carry unique IDs and generation guards where a
stale mutation could overwrite newer state. Malformed or unknown-version
documents are rejected without changing state.

Credential-bearing operations receive special handling. Wi-Fi secrets and
lock-screen passwords are never logged or persisted in generic snapshots.
Authentication remains mediated by PAM or the appropriate system service and
uses the narrowest process boundary supported by Quickshell and NixOS.

## Hyprland configuration

The root system enables the upstream NixOS Hyprland module, XWayland support,
`xdg-desktop-portal-hyprland`, and the GTK portal fallback. Niri,
Xwayland Satellite, Niri validation, KDL configuration, and Niri-specific
online binding reconciliation are removed from the active production graph.

The Sleepy Hyprland configuration is a pinned, reviewed adaptation of the
Caelestia dots rather than a mutable `caelestia install` invocation. Managed
files are immutable Home Manager sources. User overrides live in a separate
Sleepy-owned file so future upstream imports do not overwrite local choices.

Default applications are mapped to the packages already selected by Sleepy,
including Ghostty and Firefox. Keybindings launch Sleepy IPC commands and
Sleepy applications. Wallpaper, cursor, fonts, colors, blur, rounding, gaps,
animations, window rules, and special workspaces are present on first login;
no post-login bootstrap or network clone is required.

The VM host may carry a narrowly scoped renderer override required by its
`virtio-vga` device. Hardware-specific workarounds must not leak into the
general desktop profile unless they are safe on physical machines.

## Login and startup lifecycle

ReGreet remains enabled and offers the Hyprland session. Autologin is not
enabled.

After successful authentication, startup order is:

1. Hyprland establishes the Wayland session and exports its environment to the
   systemd user manager and D-Bus activation environment.
2. The graphical session target starts `sleepy-sessiond`.
3. The daemon opens durable state and all required IPC endpoints, then signals
   readiness.
4. `sleepy-shell.service` starts only after daemon readiness and receives an
   initial complete snapshot.
5. Independent helpers such as the policy agent, keyring, clipboard watcher,
   and portals join the same graphical-session lifecycle.

The shell and daemon use bounded restart policies. Restarting either component
must recover automatically without requiring a new login. Logout stops the
graphical target and all associated services, returning to ReGreet without
orphan processes.

## Persistence and migration

Existing Sleepy settings, themes, notification data, launcher state, and other
daemon-owned documents are preserved. Ordinary startup does not rewrite them.
Niri-specific generated bindings remain untouched as legacy user data but are
no longer read, generated, or required after migration.

New desktop settings use additive schema versions and transactional migration.
The first successful Hyprland generation must not destroy the ability to boot
the prior installed system generation from the bootloader.

## Testing strategy

`sleepy-sdk` and `sleepy-session` receive contract and behavior tests for every
new service, malformed inputs, degraded capabilities, reconnects, request
deduplication, timeouts, and Hyprland event reconciliation. External commands
and D-Bus peers use deterministic fakes in unit and integration tests.

`sleepy-desktop` receives QML unit tests, lint/cache generation, software-RHI
tests, IPC fixture tests, and assertions that system mutations cross the
Sleepy client boundary. A source check rejects Caelestia runtime names and
direct system-command implementations outside documented provenance files.

The root repository evaluates and builds the complete pinned component graph,
validates the Hyprland configuration, verifies the ReGreet session entry,
checks portal selection and user-unit ordering, and asserts that active Niri
packages, services, and managed configuration have been removed.

## Existing VM acceptance

Testing uses the existing libvirt domain `Sleepy` with 4 vCPUs, 8 GiB RAM, a
64 GiB qcow2 disk, SPICE graphics, virtio video, serial console, and QEMU guest
agent. Before applying a new system generation, create a named recoverable
snapshot while the domain is shut down and record its identity.

Acceptance then requires:

- build and switch the new NixOS generation inside the guest;
- boot to ReGreet and log in to the Hyprland session as `lazy`;
- confirm live Hyprland IPC and the absence of Niri processes and user units;
- confirm healthy `sleepy-sessiond` and `sleepy-shell` units with no restart
  loop or failed user/system units;
- exercise launcher, workspace switching, notification delivery, session menu,
  theme/wallpaper changes, and all VM-available system controls through Sleepy
  IPC;
- confirm unavailable virtual hardware degrades only its own controls;
- restart the daemon and shell independently and verify automatic recovery;
- log out to ReGreet and log in again without orphan processes;
- capture and visually inspect the guest framebuffer/SPICE output showing the
  real Sleepy desktop surfaces.

A process timeout or a successful package build is not visual acceptance.
Framebuffer evidence, functional IPC evidence, service status, and relevant
journal excerpts are recorded together.

## Delivery and review

Implementation uses reviewable commits by boundary: SDK contracts, daemon
services, desktop import and rename, per-domain UI adapters, Hyprland/root
integration, and VM acceptance. Root pins exact reviewed component revisions.

Before completion, an independent review agent examines architectural
ownership, GPL attribution, secret handling, direct-command escape paths,
startup lifecycle, and test evidence. Findings are verified and resolved
before any completion claim or pull request is made.
