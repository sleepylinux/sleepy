# Hyprland Sleepy Desktop Design

## Status and goal

Approved on 2026-08-30. This change replaces Niri and the current Sleepy
Quickshell UI with a branded Sleepy desktop based on the interaction model and
visual foundation of Caelestia Shell v2.4.0 and the documented behavior of the
Caelestia Hyprland dots.
ReGreet remains the login manager and Hyprland becomes the only production
compositor.

This is a source fork, not a packaged Caelestia installation. The product is
named Sleepy, its runtime paths and interfaces are owned by Sleepy, and
`sleepy-sessiond` is the authority for desktop state and system actions.
Caelestia Shell remains an attributed GPLv3 upstream, not a visible product
identity. The separately published Caelestia dots are a behavioral reference
only because that repository does not declare a source license.

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

## Upstream provenance and licensing

The only source fork authorized by this design is `caelestia-dots/shell`
v2.4.0. Its annotated, unsigned tag object
`15c41f3e19818199f653aa7dcec81d49affd7152` resolves to commit
`24aa15eefdb146350d2548c0a015b04eddbd1008`. Import tooling verifies both
identifiers before copying source.

The reviewed shell lock contains Quickshell revision
`0fed22a2c47d9568ddf13cf61586b3f2ac4378a2` with NAR hash
`sha256-OZdLL1rMR9kjTFZroOODeyQ0u6nrSxcFHlK6JUi+R/c=` and m3shapes revision
`32ad9ce328bb77ed349b40a3be10ee9ea610b8ab` with NAR hash
`sha256-YZelgEZflFNwGutX4/tIzBdbOeghJgE2oDw0uWYGxns=`. The implementation may
advance a dependency only in a separately reviewed lock update.

The `caelestia-dots/caelestia` repository has no `LICENSE`, `COPYING`, or
equivalent grant at reviewed commit
`4a635c6bf44d6415f10c09718864147584e71caa`. No file, snippet, image, or shader
from that repository is copied. Sleepy's Hyprland configuration is authored
from Sleepy requirements, Hyprland documentation, and documented user-facing
behavior. Copying becomes permissible only after an explicit compatible
license or written permission is recorded for an exact revision.

`sleepy-desktop` gains a machine-readable provenance inventory for every
imported source and asset: origin path, exact revision, SPDX expression,
copyright notice, local modification date, and disposition. GPL notices and
the complete corresponding source and build scripts ship with binary releases.
Fonts, icons, shaders, m3shapes, Quickshell modules, and generated assets are
audited independently rather than inheriting the shell repository's license by
assumption.

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
configuration directories, or product labels. Sleepy configuration and state
remain under the existing XDG `sleepy` directories. A legal/credits view and
distributed `NOTICE` remain accessible and accurate; product branding and
required attribution are separate concerns.

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

Before import, an exhaustive migration manifest classifies every upstream QML
service and native module as `render`, `move`, `rewrite`, or `drop-with-reason`.
The minimum decisions are:

| Domain | Runtime owner and mechanism |
| --- | --- |
| Tray icons and DBusMenu | shell renders daemon-forwarded, bounded models; daemon owns D-Bus subscriptions and actions |
| Clipboard history and paste | daemon owns helper lifecycle and typed entries; shell never reads clipboard files |
| Calendar and calculator | daemon providers; shell renders typed results |
| Lyrics and cover/image caching | daemon performs bounded network/file I/O; renderer receives sanitized cache handles |
| Screenshots, area selection and color picking | compositor-connected, separately sandboxed Sleepy helper started by the daemon; explicit user gesture required |
| Screencopy and recording | compositor-connected Sleepy helper with portal/Wayland handles; daemon owns policy, lifecycle and output paths |
| Keyboard layout and input-device state | Hyprland adapter in the daemon; typed device IDs and actions |
| Per-application audio | daemon PipeWire service; stable node identifiers and bounded meters |
| VPN creation and secrets | daemon NetworkManager D-Bus service plus a one-shot secret request channel |
| GPU, CPU, memory, storage, sensors and network usage | daemon resource samplers with bounded cadence |
| App database and filesystem models | daemon launcher/file providers; no unrestricted QML filesystem model |
| Settings schema, quarantine and persistence | daemon store; QML holds only validated current settings and drafts |
| Image analysis and dominant colors | non-privileged rendering helper operating only on daemon-approved cache handles |
| Blob shapes, indicators, visualiser widgets and animation helpers | retained native rendering code after namespace/license audit |
| Idle inhibitor | compositor-connected shell object leased by a typed daemon policy; lease disappears on disconnect |
| Session lock | dedicated fail-secure locker boundary described below |

No upstream domain is silently omitted. The migration manifest names its
protocol, privileges, persistence, degraded state, and component/integration
tests. A feature may be intentionally dropped only with a recorded user-facing
deviation and an approved replacement or absence.

Capabilities remain independently degradable. Missing VM hardware, such as a
backlight, battery, or Bluetooth adapter, produces a typed unavailable or
unsupported state only for that capability; it must not prevent the desktop
from becoming ready.

The shell retains the existing `$XDG_RUNTIME_DIR/sleepy/session.sock` contract
and uses purpose-specific endpoints only where secret isolation requires it.
The runtime directory is mode 0700 and sockets are mode 0600. Every accepted
peer is verified with `SO_PEERCRED` against the session UID.

Frames, nesting, strings, client queues, total clients, and per-operation time
are bounded. Slow readers and writers are disconnected; cancellation kills and
reaps owned work. Strict schemas reject unknown fields within a wire version.
A reconnect receives a complete snapshot before incremental events. Mutations
carry a unique request ID and exact expected generation, are durably
deduplicated, and report success only after confirmed readback and publication.
The Hyprland, lock, recording, and secret-agent additions extend the existing
desktop threat model before implementation.

Credential-bearing operations receive special handling. Wi-Fi secrets and
lock-screen passwords are never logged or persisted in generic snapshots.
Authentication remains mediated by PAM or the appropriate system service and
uses the narrowest process boundary supported by Quickshell and NixOS.

Network credentials use an ephemeral NetworkManager secret-agent request. A
secret is delivered over a dedicated single-use, peer-verified channel, never
appears in a snapshot/event/evidence artifact, and is retained only as required
by NetworkManager and the selected keyring policy. Cancellation and polkit
denial are typed outcomes. Suspend, logout, reboot, and power-off use fixed
logind D-Bus methods with interactive polkit; Sleepy does not install a broad
wheel-group authorization bypass.

## Fail-secure session lock

The general shell and session IPC expose `lock` but never `unlock`. Global
shortcuts and automation may request locking and query redacted lock state;
there is no programmatic unlock action.

A dedicated `sleepy-locker` process owns `ext-session-lock-v1`, creates a lock
surface for every output before declaring the session secure, and performs PAM
authentication through a private in-process PAM context. Passwords never cross
the general daemon socket, are zeroized immediately after each PAM exchange,
and are subject to bounded retries and delay. Fingerprint or other mechanisms
are disabled until separately specified and tested.

`sleepy-desktop` builds and packages `sleepy-locker` because it owns the lock
surfaces and compositor-connected client. `sleepy-session` owns lock policy,
the public typed `lock` request, the suspend gate, and redacted lock state. It
sends only a lock request over the locker-only peer-verified endpoint; the
locker is the sole authority that can authenticate and issue the Wayland
unlock-and-destroy request.

The locker is a persistent systemd user service started with and `PartOf=` the
UWSM graphical session, ordered after the Wayland environment is available,
and supervised independently of both the decorative shell and daemon. Root
NixOS configuration defines `security.pam.services.sleepy-locker`; the PAM
service file is not taken from the fork. A locker unit failure activates a
fail-safe unit that terminates the UWSM graphical session and returns to
ReGreet rather than exposing the desktop.

Password key and input-method events terminate in a native secure prompt item
inside the locker. It holds input in a mutable locked-memory buffer, passes it
directly to the PAM conversation, and explicitly zeroizes the buffer on submit,
cancel, failure, destruction, and process shutdown. QML receives only input
length and authentication status; plaintext never becomes a QML property,
JavaScript string, `QString`, log field, signal argument, or IPC frame.

Only a successful PAM result may call the Wayland unlock-and-destroy request.
Shell, daemon, or IPC clients cannot synthesize that result. If the decorative
shell crashes, the locker remains secure and shows a minimal fallback prompt.
If the daemon restarts, the locker remains secure. If the locker crashes while
secure, Hyprland's session-lock semantics must not reveal desktop content; the
system recovers to a secure locker or terminates the graphical session back to
ReGreet. Suspend waits for confirmed secure lock before proceeding.

Tests cover incorrect and empty passwords, request flooding, generic IPC and
shortcut unlock attempts, shell/daemon/locker crashes, suspend/resume,
multi-monitor coverage, monitor hotplug, and return to ReGreet. VM acceptance
includes a framebuffer check while locked and after each crash case.

## Hyprland configuration

The root system enables the upstream NixOS Hyprland module, XWayland support,
`xdg-desktop-portal-hyprland`, and the GTK portal fallback. Niri,
Xwayland Satellite, Niri validation, KDL configuration, and Niri-specific
online binding reconciliation are removed from the active production graph.

The Sleepy Hyprland configuration is authored in the root repository and
recreates the selected interaction behavior without copying the unlicensed
Caelestia dots. There is no mutable `caelestia install` invocation. The NixOS
module enables Hyprland and UWSM; Home Manager's
`wayland.windowManager.hyprland` produces the managed configuration but does
not own the session target because UWSM does. User overrides live in a separate
Sleepy-owned file so system updates do not overwrite local choices.

Default applications are mapped to the packages already selected by Sleepy,
including Ghostty and Firefox. Keybindings launch Sleepy IPC commands and
Sleepy applications. Wallpaper, cursor, fonts, colors, blur, rounding, gaps,
animations, window rules, and special workspaces are present on first login;
no post-login bootstrap or network clone is required.

The root lock records the exact nixpkgs, Home Manager, Quickshell, m3shapes,
Hyprland, and imported shell revisions and hashes. `hyprland --verify-config`
(or the exact validation interface exposed by the pinned Hyprland build)
validates the generated file in CI and inside the guest.

Portal routing prefers `xdg-desktop-portal-hyprland` for screencast and
screenshot interfaces and uses `xdg-desktop-portal-gtk` only for GTK/file
chooser interfaces it implements. Acceptance exercises a PipeWire screencast,
a Firefox file chooser, and settings portal behavior without competing portal
backends.

The `hosts/sleepy-vm` guest module may carry a narrowly scoped renderer override
required by the detected `virtio-vga` device. Hardware-specific workarounds do
not enter the general desktop profile unless they are safe on physical
machines.

## Login and startup lifecycle

ReGreet remains enabled and offers the Hyprland session. Autologin is not
enabled.

ReGreet starts the UWSM-provided Hyprland session entry. UWSM owns environment
import, the compositor scope, and the graphical session target. The exact
target name is resolved from the pinned UWSM/NixOS module during implementation
and asserted by the root contract rather than duplicated as an unchecked
literal.

After successful authentication, startup order is:

1. Hyprland establishes the Wayland session and exports its environment to the
   systemd user manager and D-Bus activation environment.
2. The graphical session target starts `sleepy-sessiond`.
3. `sleepy-sessiond` runs as `Type=notify`, opens durable state and every public
   IPC endpoint, then emits `READY=1`.
4. `sleepy-shell.service` starts only after daemon readiness and receives an
   initial complete snapshot.
5. Independent helpers such as the policy agent, keyring, clipboard watcher,
   and portals join the same graphical-session lifecycle.

The shell has `Wants=` and `After=` ordering on the daemon but not a strong
`Requires=` failure coupling: it retries a missing socket with bounded backoff
and reconnects after daemon restart. Both services use bounded restart and
start-limit policies and are `PartOf=` the UWSM graphical session. Logout stops
that target and all associated services, returning to ReGreet without orphan
processes.

## Persistence and migration

Existing Sleepy settings, themes, notification data, launcher state, and other
daemon-owned documents are preserved. Ordinary startup does not rewrite them.
Niri-specific generated bindings remain untouched as legacy user data but are
no longer read, generated, or required after migration.

New desktop settings use separate versioned files. Migration uses the existing
descriptor-relative no-follow, ownership, exclusive-temporary, atomic-rename,
file-fsync, directory-fsync, journal, and startup-reconciliation guarantees.
Legacy documents remain byte-for-byte untouched until an explicit future
retirement release. Home Manager refuses collisions with user-owned Hyprland
or Sleepy override paths instead of replacing them silently.

The first successful Hyprland generation must not destroy the ability to boot
the prior installed system generation from the bootloader. Acceptance performs
a Hyprland login and mutation, boots the prior Niri generation, verifies its
legacy bytes and essential session behavior, then returns to the Hyprland
generation.

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

## Feature parity and objective acceptance

The import manifest maps every v2.4.0 surface and behavior to a Sleepy test or
an approved deviation. At minimum it covers:

| Area | Required objective cases |
| --- | --- |
| Bar/taskbar/workspaces | active, occupied, special and per-monitor workspaces; tray icon and DBusMenu action |
| Launcher | apps, calculation, scheme and wallpaper modes; keyboard navigation; safe launch failure |
| Dashboard/sidebar | media, calendar, weather, resources and notification history in online/offline states |
| OSD | volume, mute, microphone, brightness and power events with unavailable hardware states |
| Lock/session | PAM success/failure, crash cases, suspend gate, logout and power-action denial |
| Network/Bluetooth/audio | enumerate, connect/change, secret prompt, device loss and independent degradation |
| Media/lyrics | multiple players, metadata updates, missing art/lyrics and transport failure |
| Utilities | idle inhibit, recording start/pause/stop, screenshot/selection, color picker and game mode |
| Window/compositor | focus, move, close, fullscreen, groups, special workspaces and monitor hotplug |
| Appearance | wallpaper/theme change, blur/opaque, reduced motion, 1x/2x scale and two monitors |

Reference captures are produced from the exact upstream v2.4.0 shell in a
disposable fixture environment containing no user data. Sleepy comparisons use
fixed fixtures, monitor geometry, scale, wallpaper, fonts, locale, clock, and
animation-rest state. Layout anchors, surface presence, clipping, overflow, and
semantic colors are pass/fail assertions; pixel tolerances cover renderer
antialiasing without accepting missing or substantially displaced surfaces.

## Existing VM acceptance

Testing uses the existing libvirt domain `Sleepy` with 4 vCPUs, 8 GiB RAM, a
64 GiB qcow2 disk, SPICE graphics, virtio video, serial console, and QEMU guest
agent. Before applying a new system generation, follow a committed VM runbook.
It records inactive domain XML, UEFI NVRAM, disk paths, formats, backing chains,
and checksums while the domain is shut down. Because libvirt snapshots do not
uniformly include writable NVRAM, the runbook chooses and verifies an offline
disk copy or supported snapshot plus separate NVRAM/XML copies. It performs a
restore drill before the destructive switch, defines failure triggers and
exact restore commands, and retains the baseline until final acceptance.

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

Evidence is written beneath a newly created mode-0700 run directory with
mode-0600 files. Collection redacts SSIDs, notification text, credentials,
document paths, device names, and unrelated journal fields. The report records
artifact hashes, permitted reviewers, and a deletion date; raw captures are
deleted after review unless the user explicitly requests retention.

## Delivery and review

Implementation order is SDK contracts, daemon services, desktop import and
rename, per-domain UI adapters, and root Hyprland integration. Each boundary
has a compatible revision checkpoint. The root pins only a mutually compatible
set of reviewed component revisions before VM acceptance; partial cross-repo
graphs are never promoted.

Before completion, an independent review agent examines architectural
ownership, GPL attribution, secret handling, direct-command escape paths,
startup lifecycle, and test evidence. Findings are verified and resolved
before any completion claim or pull request is made.
