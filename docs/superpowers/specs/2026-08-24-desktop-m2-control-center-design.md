# Sleepy Desktop Milestone 2 Control Center Design

## Status

Approved by continuation of the Variant B desktop direction and the explicit
2026-08-24 instruction to implement the full plan. This document narrows the
next independently releasable slice; it does not reduce the overall Sleepy
desktop goal.

## Goal

Turn the Milestone 1 rail and placeholder drawer into a polished, keyboard-first
Control Center backed by real system state. Users can manage named presets and
editable bindings without an update overwriting their state. The visual system
uses consistent icons, layered cozy-night glass materials, lavender color, and
dense but calm information hierarchy inspired by Caelestia and end-4.

## Scope and sequencing

Milestone 2 ships one complete vertical slice across `sleepy-sdk`,
`sleepy-session`, `sleepy-artwork`, `sleepy-desktop`, and the root `sleepy`
distribution. It includes the shared foundations required by later
notification, dashboard, media, calendar, power, overview, and theme-editor
surfaces.

This milestone does not ship those later surfaces, a third-party plugin
runtime, installer, or release image. Those remain required by the overall
project and follow this milestone rather than being replaced by it.

## Product behavior

### Rail and Control Center

The inset left rail remains 72 px wide with a 12 px outer inset. Its bottom
Control Center trigger is an actual named icon and has a default global action
`surface.controlCenter.toggle`. The same action toggles the drawer from the
keyboard. Escape closes it, and focus returns to the exact invoking control on
the correct display.

The global action crosses a stable Quickshell IPC boundary named `sleepy`.
Niri spawns an argv-only IPC call; the shell resolves the target from Niri's
focused workspace/output state and records keyboard invocation provenance so
focus returns to that display's rail trigger. Unknown actions or unavailable
outputs fail without changing the open surface.

The Control Center is a scrollable glass drawer, 408 px by default, which stays
usable at 768 px height. It contains:

- a clock/date and session header with lock, logout, and power actions;
- network and Bluetooth status with connected-name/detail;
- volume, mute, microphone, output-device, and brightness controls;
- night-light control; focus/do-not-disturb arrives with the notification
  service rather than being presented as a fake local toggle;
- battery and power-profile status where supported;
- current media title, artist, playback state, and controls where supported;
- compact system status chips and a visible adapter diagnostic;
- a named-preset selector and entry into preset/binding management.

Unsupported hardware is presented honestly. A missing battery or backlight
removes or disables only that control; it never disables the drawer. Mutations
show a busy state, update only after confirmed readback, and preserve the last
valid state when an adapter fails or returns malformed data.

### Presets

Built-in presets remain immutable package inputs. Editing a built-in creates a
new user-owned UUID preset. User presets support create-from-current,
duplicate, rename, activate, delete, import, and export. Deleting the active
preset is rejected until another preset is activated.

Duplicate names are allowed because identifiers are authoritative. The UI
shows the user-facing name and a short identifier when disambiguation is
needed. Import is conflict-safe: a built-in is always copied to a new user ID;
an existing user ID is rejected unless the user explicitly selects replace;
replace can never target a built-in.

`$XDG_CONFIG_HOME/sleepy/settings.json` and
`$XDG_STATE_HOME/sleepy/presets.json` remain the authoritative durable state.
Home Manager must never own or overwrite them. Newly packaged defaults affect
only built-ins and newly created copies; missing actions in an existing user
preset remain unbound.

### Keybindings

Bindings map semantic actions to canonical accelerators. Editable actions
include terminal, launcher, window/workspace navigation, Control Center,
session actions, media, volume, and brightness. Physical chords do not appear
inside QML business logic.

Session action identifiers are exact: `session.lock`, `session.logout`,
`session.reboot`, and `session.powerOff` request those closed actions;
`session.power` is retained as the non-destructive action that opens the power
chooser through `openPowerMenu()` and never means immediate power-off.

Canonical modifier order is `Mod`, `Ctrl`, `Alt`, `Shift`, followed by one key.
The contract rejects blank actions, unknown or duplicate modifiers, missing or
multiple keys, and duplicate canonical chords. Comparison happens after
canonicalization. UI conflict feedback names both actions before any write.

Input is trimmed only at the document boundary; whitespace inside a chord is
invalid. Single ASCII letters canonicalize to uppercase, digits remain exact,
`F1..F24` canonicalize uppercase, and common XKB names use an explicit mapping
for Return, arrows, navigation, media, and brightness keys. Other XKB tokens
must match `[A-Za-z0-9_]+` and remain case-sensitive; the complete generated
KDL still requires Niri validation. SDK `SemanticAction`,
`KeybindingConflict`, and `ConflictKind` types provide structured invalid,
duplicate, and reserved-core results.

An immutable minimal recovery include remains outside preset state. Its sole
binding is `Mod+Shift+Escape` for `recovery.shell`; the SDK exports this exact
reserved-core map and normal preset validation always checks against it. It
exists only to recover a broken user configuration and is not part of the
editable semantic-action registry.

The packaged `builtin.sleepy` preset contains the complete normal M2 default
bindings, including terminal, launcher, navigation, and Control Center. The
core include contains only recovery. First initialization therefore never
turns the effective binding set into an empty file.

Editing bindings while the active preset is built-in is copy-on-write: the
orchestrator creates a UUID user copy, applies the edit, activates the copy,
installs its generated include, and confirms reload as one recoverable
operation. Full-document update and import-replace of the active preset use the
same orchestration path or are rejected unless application is requested.

Activating or changing bindings compiles the active preset into a generated
`sleepy-user-bindings.kdl`. The compiler validates the complete candidate Niri
configuration before atomically replacing the generated include and requesting
a Niri reload. Durable preset state and the last valid generated include remain
recoverable on validation, write, or reload failure.

Activation and active-preset binding edits use one orchestration operation,
not separate user-visible `activate` and `apply` steps. Under the store lock it
compiles and validates the candidate include, records the previous settings and
include, commits the new settings/include, and requests reload. A failed install
or reload restores both previous artifacts and reloads the previous config.
The structured result distinguishes committed, rolled-back-confirmed, and
commit-state-unknown outcomes; it never reports success while the effective
Niri config is unconfirmed.

Because presets, settings, and the generated include cross XDG roots, the
orchestrator maintains a synced transaction journal with old/new hashes,
same-directory durable old/new artifact files, and phases `prepared`,
`presetCommitted`, `settingsCommitted`, `bindingsCommitted`, `reloadPending`,
and `reloadConfirmed`. No old artifact is removed until the confirmed phase and a
synced journal clear. Startup reconciliation either finishes the confirmed
candidate or restores all previous artifacts and reloads the previous config.
Fault/termination tests cover every rename, fsync, reload, and cleanup boundary.

## Contract model

The existing JSON shape stays at `schemaVersion: 1`; no disk migration is
needed for this slice. Semantic validation is added without silently rewriting
existing files. `sleepyctl presets validate` and binding mutation commands
report invalid legacy values, leaving original bytes untouched.

The SDK adds:

- canonical accelerator parsing and formatting;
- known semantic action identifiers for the packaged preset;
- structured duplicate/reserved/invalid conflict records;
- validation helpers for preset keybindings;
- typed system snapshot, state-mutation result, and session-action result
  documents shared by session and desktop adapters.

`SystemMutation` is a tagged enum, so every stateful capability has one exact
value type. `SystemMutationResult` carries that request, a monotonically
increasing `generation`, and the confirmed post-mutation snapshot. Logout,
reboot, power-off, and lock are not state mutations: `SessionAction` and
`SessionActionResult` report `initiated|failed` plus a diagnostic and never
pretend that a post-session snapshot is possible. Per-capability diagnostics use strict kinds:
`unsupported`, `busy`, `timeout`, `parse`, or `command`, plus a non-secret
message. These are wire contracts, not strings inferred by the desktop.
The SDK exposes `validate_system_snapshot`, `validate_system_mutation_result`,
and `validate_session_action_result`; strict fixtures define every field and
capability key consumed by the desktop.

The closed `CapabilityId` wire keys are `network.enabled`,
`bluetooth.enabled`, `audio.volume`, `audio.muted`,
`audio.microphoneLevel`, `audio.microphoneMuted`, `audio.outputDevice`,
`display.brightness`, `display.nightLightEnabled`, `power.profile`,
`battery.status`, and `media.transport`. Capability and diagnostic maps use
this enum; unknown keys are invalid. `battery.status` is read-only. Separate
closed session actions are `lock`, `logout`, `reboot`, and `powerOff`.
`SystemSnapshot.sessionActions` is a strict map from every `SessionAction` to
its `CapabilityState`, so the shell can gate unavailable actions without
pretending they are state mutations.

`AudioState` exposes `outputDeviceId` plus selectable
`AudioOutputDevice { id, label, isDefault }` records; UI never sends a display
label as a sink identifier. `PowerState` exposes a typed current profile and
available `power-saver|balanced|performance` profiles. Media transport accepts
only `playPause|next|previous`. Snapshot and both result documents carry a
generation supplied by the requesting desktop adapter and echoed unchanged by
the process-per-request CLI. The desktop increments its counter before every
show/set/perform request; stale lower generations never replace newer state.

The complete preset document remains the import/export unit. A bundle format is
not introduced.

## Session and system adapters

`sleepy-session` remains the owner of durable Sleepy state and gains two
boundaries:

1. Preset mutation/import/export and binding compilation APIs.
2. A typed system adapter facade with injectable command execution for tests.

The first system facade uses bounded, explicit platform tools already suited to
the target NixOS desktop:

- NetworkManager through `nmcli`;
- BlueZ through `bluetoothctl`;
- PipeWire through `wpctl`;
- brightness through `brightnessctl` where a backlight exists;
- power profiles through `powerprofilesctl`;
- battery through UPower;
- media through `playerctl`;
- night light through a managed user `gammastep` service;
- lock through packaged `swaylock`; logout, reboot, and power through a Control
  Center confirmation surface before the session facade invokes fixed Niri or
  `systemctl` argument arrays; these semantic actions are never compiled to a
  direct destructive binding;
- Niri through its message interface for validated reload/application.

Commands use fixed argument arrays, explicit timeouts, structured errors, and
no shell interpolation. Parsers are pure and fixture-tested. `system show`
returns one typed snapshot and typed state mutations return a
`SystemMutationResult` containing confirmed readback. Session actions return a
separate `SessionActionResult` because logout/reboot/power-off cannot provide a
post-action snapshot. Independent probes
fan out concurrently under a total 1200 ms deadline; the desktop timeout is
1800 ms and its poll interval is at least 3000 ms. Results carry request
generations so stale completions cannot replace newer state. The desktop may
request an immediate refresh after a mutation. A future D-Bus daemon can
replace transport without changing the documents or QML state interfaces.

Semantic validation must not make recovery depend on opening a fully valid
store. A raw `StateInspector` reads settings/preset bytes without initializing
or rewriting them and reports record/action errors. A journaled repair bundle
contains complete replacement settings plus preset collection; the binding
orchestrator validates their cross-reference, compiles the generated include,
creates a synced non-overwriting directory containing the original malformed
bytes, and applies all three artifacts through the normal transaction. Normal
mutations remain disabled until inspection is clean or repair is confirmed.

## Desktop architecture

### Materials

`EffectsPolicy` derives material behavior from `effectsProfile` and
`reducedMotion`:

- `full`: translucent layered surfaces, highlight stroke, soft shadow, glow,
  and normal motion;
- `reduced`: higher opacity, no decorative glow, shorter motion;
- `none`: opaque high-contrast surfaces, no shadow or non-essential motion.

Glass is never implemented as low-contrast transparency alone. Text and
controls retain contrast over bright and dark wallpapers. Compositor backdrop
blur is optional capability enhancement; the material remains coherent without
it.

### Icons

Functional Unicode glyphs are removed. `sleepy-artwork` owns a small coherent
set of GPL-3.0-only SVG icons exposed by logical manifest names. `IconRegistry`
resolves only those names, and `SleepyIcon` supplies consistent size, color,
and accessibility behavior. Missing icons render a visible diagnostic symbol
without crashing the shell.

The desktop package receives substituted artwork-root and manifest paths.
`SleepyIcon` uses a Qt 6 `MultiEffect` mask/colorization path so `currentColor`
SVG assets follow the requested QML color; package and pixel tests prove both
resolution and tinting.

### Surfaces and navigation

The M1 one-open-surface controller is generalized around descriptors with
`id`, `edge`, `width`, `triggerIcon`, `triggerLabel`, availability, and initial
focus target. The first descriptor is `controlCenter`; later surfaces register
through the same interface.

Descriptors also carry `availability` and a stable `initialFocusKey`. Each
per-screen view resolves that key to its own Item; descriptors never store a
QML Item shared across `Variants` instances.

The shell declares `//@ pragma ShellId sleepy`, while Home Manager separately
runs the named Quickshell config `sleepy`. `IpcHandler` target `sleepy` exposes
typed `toggleControlCenter(): void`, `openControlCenter(): void`,
`closeActiveSurface(): void`, `openPowerMenu(): void`, and
`requestSessionAction(action: string): void`.
The latter validates the closed session-action names and opens the appropriate
confirmation surface; lock may run directly. Generated KDL uses exact argv
`quickshell ipc --config sleepy call sleepy <method> [argument]`.
`ShortcutRouter` maps those calls to semantic actions; it does not own physical
keys. Every keyboard IPC invocation performs a fresh bounded Niri
focused-output query and changes surfaces only after a successful result,
avoiding normal workspace polling delay.

Interactive widgets expose accessible names and roles. Arrow navigation is
explicit within grids, Tab traversal never traps focus, Home/End work for lists,
disabled controls are skipped, Escape closes the active surface, and focus
restoration is screen-scoped.

The preview becomes a deterministic surface gallery with full/reduced/none
effects, dark/light palettes, compact/tall viewports, fixture system state, and
visible focus states. It is a visual-development tool, not the authoritative
settings store.

## Root integration

The root flake pins reviewed component revisions and consumes component-owned
checks. Root CI must test the external desktop package, not only retained
fallback QML.

NixOS enables NetworkManager, PipeWire, BlueZ, UPower, and power profiles. The
desktop user environment contains the explicit adapter tools. Hardware absence
remains a supported runtime state.

Niri includes two binding files:

```kdl
include "bindings-core.kdl"
include optional=true "sleepy-user-bindings.kdl"
```

Home Manager owns only `bindings-core.kdl` and the surrounding static config.
An idempotent pre-Niri Home Manager activation invokes session initialization
to create the generated user include only when absent. The root pins and asserts
Niri 26.04 or newer, whose optional include also keeps a pristine login usable
if initialization fails. Thereafter the include is owned by the Sleepy session
layer. Update-safety checks prove that rebuilding or upgrading does not alter
settings, presets, or the generated include.

Binding validation accepts an ownership-checked `BindingPaths` containing the
real Niri config root, fixed generated include, and journal. The config root,
generated include, journal, and their writable parents must remain inside the
expected XDG roots and must not traverse symlinked writable directories. Static
Home Manager files may be symlinks only when their fully resolved targets are
regular root-owned files inside `/nix/store`; validation copies their resolved
bytes. The generated include, journal, backups, and temporary files must be
regular user-owned files with bounded modes and no symlinks. Validation stages
a copy of the exact current config tree, substitutes only the candidate include,
and runs the pinned Niri validator on that tree; session-owned static fixtures
are not sufficient release evidence.

The old in-tree shell and branding fallbacks are deleted only after the
external shell tests, live drawer interaction, VM state-preservation, and
visual gates pass for one pinned candidate.

## Error handling and recovery

- Every durable mutation validates a complete candidate before replacement.
- Same-directory temporary files, file sync, atomic rename, and directory sync
  remain mandatory.
- Built-in mutation returns a structured immutable-preset error.
- Adapter timeout, unsupported hardware, malformed output, and command failure
  are distinct states.
- Binding application never removes the last valid generated include on
  compiler or reload failure.
- Online apply subscribes to and drains the Niri event stream before the
  candidate rename, persists `reloadPending`, explicitly invokes
  `niri msg action load-config-file --path <trusted-config.kdl>`, then requires
  the next `ConfigLoaded { failed: false }` within a bounded timeout. A
  failed/timeout candidate is rolled back and the
  rollback must receive its own successful `ConfigLoaded` event; otherwise the
  result is commit-state-unknown.
- Pre-Niri activation performs only offline initialization or file-level
  rollback and leaves a `reloadPending` journal phase. A separate user service
  ordered after `niri.service` completes online reconciliation and confirmation.
- Preset activation and effective binding application are one recoverable
  transaction with explicit rollback confirmation.
- Raw state inspection and repair remain available when normal store open
  rejects legacy semantic errors.
- Core recovery bindings and previous NixOS generations remain available.
- Lock can execute directly; logout, reboot, and power bindings open an
  argv-only IPC confirmation surface with cancel/confirm/focus tests and never
  invoke destructive commands directly from generated KDL.
- No test, update, or deployment deletes user state or performs garbage
  collection.

## Verification

### Component tests

- SDK fixtures prove accelerator canonicalization and every invalid/conflict
  class, system document compatibility, and strict unknown-field behavior.
- Session tests prove every preset operation, built-in immutability, import
  modes, active-delete rejection, failed-write byte preservation, concurrent
  mutation serialization, binding compiler output, command timeout, malformed
  adapter payloads, unsupported capabilities, and confirmed readback.
- Desktop Qt tests prove effects policies, icon coverage, descriptor-driven
  surfaces, keyboard navigation, accessibility, compact/tall layout, last-valid
  state preservation, busy/error states, and preset management flows.
- Component packages expose their tests as Nix flake checks.
- Artwork exposes `checks.assets`; desktop exposes QML, package, and preview
  checks; root builds the exact pinned input check attributes.

### Distribution and VM gates

- Root source, license, lock, update-safety, Niri, component, and service
  contracts pass.
- Full `nix flake check` and explicit component/toplevel/Home Manager builds
  pass in the NixOS VM.
- A seeded pristine-home test runs old and new Home Manager activation plus
  session initialization and proves settings, presets, and generated bindings
  remain byte-identical after every phase.
- Two-phase deployment proves settings, presets, and generated bindings remain
  byte-identical unless the acceptance action intentionally changes them.
- Before deployment, acceptance creates a named user preset, assigns a
  non-reserved Control Center binding, activates/applies it, and records the
  preset plus generated-include hashes. Both survive dry, test, permanent,
  Home Manager, and service restart gates.
- A keyboard action opens the live Control Center, Escape closes it, and focus
  returns to the invoking rail control.
- Final screenshots cover 1280×800 and a compact viewport, full and no-effects
  modes, the Control Center main page, preset list, and binding-conflict state.
- Runtime/profile, SSH, Niri, Quickshell, session service, and previous
  generations remain healthy after permanent switch.

## Completion boundary

Milestone 2 is complete only when the real VM uses the pinned external
components, all controls either perform confirmed mutations or clearly report
unsupported state, named presets and bindings survive an update, and the live
keyboard/mouse/visual acceptance gates pass. Passing isolated QML tests alone
is not completion.
