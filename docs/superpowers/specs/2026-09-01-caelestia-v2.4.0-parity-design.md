# Caelestia v2.4.0 Full-Parity Sleepy Shell Design

## Status and scope

Approved in chat on 2026-09-01. This document supersedes the service-boundary
and parity-deviation decisions in
`2026-08-30-hyprland-sleepy-desktop-design.md`. Requirements in that document
remain in force unless this document explicitly replaces them.

Sleepy Shell will expose the complete Caelestia Shell v2.4.0 interface with
the same surfaces, geometry, typography, colors, effects, animation timing,
state transitions, interactions, keyboard behavior, multi-monitor behavior,
and user-visible features. The only intentional visual differences are Sleepy
product naming and Sleepy-owned brand artwork. There are no final
`approved-deviation` feature outcomes.

The exact upstream is the GPL-3.0-only `caelestia-dots/shell` v2.4.0 tag object
`15c41f3e19818199f653aa7dcec81d49affd7152`, resolving to commit
`24aa15eefdb146350d2548c0a015b04eddbd1008`. The unlicensed
`caelestia-dots/caelestia` dots repository remains a behavior-only reference;
no source or asset is copied from it.

## Chosen architecture

Sleepy uses a minimally modified, modular source fork rather than a visual
reimplementation. The imported upstream `components`, `modules`, `services`,
`utils`, assets, shaders, and native rendering helpers form the production
graph. Existing reduced `Core*` replacement surfaces are retired once their
corresponding upstream modules load and pass parity tests.

Upstream organization remains recognizable so individual features can be
changed or rebased later. Sleepy-specific behavior is isolated in small
namespace, branding, packaging, compatibility, and security patches. A
machine-readable patch inventory maps every local change to its reason and
test. Broad rewrites of visual files are rejected when an adapter or narrowly
scoped patch can preserve upstream behavior.

The production package is a Sleepy product, not a Caelestia installation. It
must not require or create a `caelestia` executable, process, systemd unit, IPC
endpoint, configuration directory, state directory, cache directory, command,
or visible product label. GPL attribution remains in `NOTICE`, source
provenance, and the legal/credits surface.

## Module boundaries

The production tree retains these independently testable responsibilities:

- `components/`: reusable controls and visual primitives;
- `modules/`: bar, taskbar, background, launcher, dashboard, sidebar,
  notifications, OSD, overview/window information, session menu, utilities,
  wallpaper/style views, and per-monitor surfaces;
- `services/`: narrowly scoped state and action providers used by modules;
- `utils/`: pure formatting, search, image, path, and model helpers;
- `plugin/`: native QML types for blobs, shapes, animation helpers, settings,
  images, models, and performance-sensitive rendering;
- `adapters/`: Sleepy-only compatibility objects where a direct upstream
  provider cannot be retained safely or where an existing Sleepy daemon
  already provides the exact required behavior;
- `branding/`: Sleepy names, logo selection, defaults, and legal attribution;
- `locker/`: independently supervised fail-secure Sleepy session locker.

Feature modules may depend on components, utils, service interfaces, and
audited native QML types. They must not depend on another feature module's
private implementation. Sleepy adapters must expose the upstream-facing API
expected by the visual module so visual source does not accumulate backend
conditionals.

## Runtime integrations

Direct integrations used by the upstream shell are allowed when they preserve
behavior and do not create a Caelestia runtime dependency. This includes
Quickshell's Hyprland, PipeWire, UPower, MPRIS, Notifications, SystemTray, PAM,
and other supported service modules, plus fixed-argv invocation of installed
system utilities such as `hyprctl`, `nmcli`, `bluetoothctl`, `wpctl`,
`brightnessctl`, `powerprofilesctl`, `wl-copy`, `swappy`, and desktop
applications.

Direct execution follows these rules:

1. QML passes an argument vector directly to `Process` or
   `Quickshell.execDetached`; it does not build a command for `sh -c`, `bash
   -c`, `fish -c`, `eval`, or equivalent interpretation.
2. User-controlled values occupy a single argument and are validated to the
   domain expected by the called program.
3. Credentials, authentication material, and NetworkManager secrets never
   appear in argv, environment dumps, logs, snapshots, evidence, or generic
   shell properties.
4. Operations report real completion or failure and refresh observable state;
   the UI does not permanently commit an optimistic state that the system did
   not accept.
5. Commands have bounded lifetime and output where an upstream process can
   hang or emit unbounded data.

Existing `sleepy-sessiond` protocol-v3 services remain available and may back
an adapter when they already match the upstream contract. They are no longer a
mandatory path for ordinary compositor, network, audio, media, tray, or power
interactions. No duplicate state authority is introduced inside one feature:
each module selects exactly one provider for a given state/action pair.

## Sleepy identity conversion

All active imports and native namespaces use `Sleepy`, not `Caelestia`.
Runtime configuration, state, cache, data, sockets, and per-monitor overrides
use the standard XDG roots under `sleepy`. Upstream CLI calls are mapped to a
Sleepy command with the same user-visible result or replaced by the direct
provider responsible for that feature.

Strings visible to users identify Sleepy. Sleepy artwork replaces upstream
product marks without changing surrounding geometry or animation. Tests reject
active Caelestia imports, executable names, unit names, socket names, XDG
paths, IPC commands, and visible labels while allowing provenance, copyright,
license, migration fixtures, and comparison metadata.

## Settings and customization

The complete upstream settings surface is retained, including appearance,
animation duration, transparency, rounding, spacing, padding, fonts,
per-monitor settings, bar composition, launcher behavior, dashboard, sidebar,
notifications, OSD, lock appearance, utilities, wallpaper, and service
preferences.

Defaults reproduce Caelestia v2.4.0 exactly except for Sleepy branding and
Sleepy-selected default applications. Sleepy stores settings beneath its XDG
namespace. Unknown compatible keys survive a read/write cycle so future
upstream additions are not destroyed. Invalid settings are quarantined with a
diagnostic and the last valid/default configuration keeps the shell usable.

The modular upstream schema and attached configuration types remain the public
customization boundary. Feature-specific overrides stay with their feature;
global visual tokens stay centralized. Sleepy-specific additions use their own
namespace and do not fork an upstream property for unrelated purposes.

## Security exceptions

Visual and ordinary desktop parity does not weaken the existing fail-secure
lock boundary. `sleepy-locker` remains the only unlock authority, owns
`ext-session-lock-v1`, keeps passwords out of QML/IPC, authenticates with PAM,
and survives decorative-shell or daemon failure. The Caelestia lock interface
is reproduced visually and behaviorally on top of this boundary.

Suspend waits for confirmed lock. Logout, reboot, and power-off remain fixed,
auditable operations and cannot accept arbitrary command text. Secret-bearing
Wi-Fi flows use NetworkManager's secret mechanism or a narrow protected helper,
not `nmcli` command-line passwords. These are implementation boundaries, not
approved user-visible deviations.

## State flow and failures

Each feature has one provider that publishes an initial snapshot and later
updates. The corresponding module renders loading, available, empty,
unsupported, permission-denied, disconnected, and failure states matching the
upstream presentation. Provider restart or Hyprland reload triggers bounded
reconnection and a fresh snapshot without requiring a shell restart.

Unavailable VM hardware degrades only its feature. A missing battery,
backlight, Bluetooth adapter, sensor, GPU provider, or media player cannot
prevent the bar, launcher, dashboard, or remaining controls from loading.
Failed mutations produce the same visible affordance/toast behavior as
upstream and then reconcile from observed state.

## Parity requirements

The existing 403-entry parity manifest is revised so every reachable upstream
v2.4.0 surface and behavior ends at `verified`. An entry may be excluded only
when the upstream file is unreachable, build-only, a license document, or a
non-redistributable asset; an excluded visual asset receives a dimensionally
and behaviorally equivalent Sleepy-owned replacement. `approved-deviation` is
not a completion status.

Deterministic reference sessions run upstream v2.4.0 and Sleepy with identical
monitor geometry, scale, fonts, locale, clock, wallpaper, fixtures, and
interaction scripts. Static checkpoints use pixel comparison with masks only
for Sleepy branding and explicitly dynamic user content. Layout bounds,
clipping, text metrics, opacity, color, and surface presence are asserted
separately so antialiasing tolerance cannot hide a missing or displaced
component.

Animation verification captures the same timestamped frames after each
interaction and compares duration, delay, easing, path, opacity, scale,
deformation, clipping, and final state. Reduced-motion and effects-disabled
profiles receive their own references. Required scenarios cover one and two
monitors, mixed 1x/2x scale, monitor hotplug, full-screen suppression,
keyboard-only navigation, pointer/touch gestures, and every upstream module.

## Verification and VM acceptance

Component verification includes QML lint/cache generation, native plugin
builds and tests, production-graph load tests, command-safety checks, runtime
identity checks, settings round trips, feature interaction tests, reference
captures, frame comparison, and Nix package checks. Existing SDK/session tests
remain green even when a UI feature uses a direct provider.

The root repository builds the exact pinned component graph and validates
Hyprland, UWSM, ReGreet, portals, user-service ordering, rollback, and absence
of active Niri configuration. The existing automated Hyprland production VM
check must pass from a clean checkout.

Final acceptance uses the existing libvirt `Sleepy` domain through
virt-manager after taking and verifying an offline rollback bundle. It covers
interactive ReGreet login, every shell surface, all available controls,
degraded hardware, notifications, launcher modes, workspaces and special
workspaces, wallpaper/style changes, media, network, audio, utilities, secure
lock, suspend/resume, logout, shell/daemon/locker restart recovery, portals,
multi-monitor behavior, and bootloader rollback to the prior generation.

Reference and Sleepy screenshots plus animation evidence are reviewed at the
same guest resolution and scale. A package build, offscreen QML test, or
structural similarity alone is not visual acceptance. The acceptance record
contains redacted evidence hashes and no credentials or unrelated user data.

## Completion criteria

The work is complete only when:

- the full upstream visual graph is active and the reduced `Core*` substitute
  is no longer the production interface;
- all reachable v2.4.0 features work under Sleepy identity;
- no active Caelestia runtime dependency or product label remains;
- all parity entries are verified or are non-runtime exclusions with an
  equivalent Sleepy-owned visual replacement where necessary;
- deterministic static and animation comparisons pass;
- automated repository, package, and production-VM checks pass;
- real virt-manager acceptance and rollback evidence are complete;
- the feature branches are clean, mutually pinned, and ready for integration.
