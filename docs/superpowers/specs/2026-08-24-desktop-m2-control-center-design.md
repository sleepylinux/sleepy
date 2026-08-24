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

The Control Center is a scrollable glass drawer, 408 px by default, which stays
usable at 768 px height. It contains:

- a clock/date and session header with lock, logout, and power actions;
- network and Bluetooth status with connected-name/detail;
- volume, mute, microphone, output-device, and brightness controls;
- night-light and focus/do-not-disturb controls;
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

Canonical modifier order is `Mod`, `Ctrl`, `Alt`, `Shift`, followed by one key.
The contract rejects blank actions, unknown or duplicate modifiers, missing or
multiple keys, and duplicate canonical chords. Comparison happens after
canonicalization. UI conflict feedback names both actions before any write.

An immutable minimal recovery include remains outside preset state. It exists
only to recover or reload a broken user configuration and does not duplicate
normal editable actions.

Activating or changing bindings compiles the active preset into a generated
`sleepy-user-bindings.kdl`. The compiler validates the complete candidate Niri
configuration before atomically replacing the generated include and requesting
a Niri reload. Durable preset state and the last valid generated include remain
recoverable on validation, write, or reload failure.

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
- typed system snapshot and mutation result documents shared by session and
  desktop adapters.

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
- Niri through its message interface for validated reload/application.

Commands use fixed argument arrays, explicit timeouts, structured errors, and
no shell interpolation. Parsers are pure and fixture-tested. `system show`
returns one typed snapshot and `system set <capability> <value>` returns a
post-mutation snapshot after readback. The desktop polls at a modest interval
and may request an immediate refresh after a mutation. A future D-Bus daemon
can replace transport without changing the documents or QML state interfaces.

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

### Surfaces and navigation

The M1 one-open-surface controller is generalized around descriptors with
`id`, `edge`, `width`, `triggerIcon`, `triggerLabel`, availability, and initial
focus target. The first descriptor is `controlCenter`; later surfaces register
through the same interface.

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
include "sleepy-user-bindings.kdl"
```

Home Manager owns only `bindings-core.kdl` and the surrounding static config.
The generated user include is initialized once and thereafter owned by the
Sleepy session layer. Update-safety checks prove that rebuilding or upgrading
does not alter settings, presets, or the generated include.

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
- Core recovery bindings and previous NixOS generations remain available.
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

### Distribution and VM gates

- Root source, license, lock, update-safety, Niri, component, and service
  contracts pass.
- Full `nix flake check` and explicit component/toplevel/Home Manager builds
  pass in the NixOS VM.
- Two-phase deployment proves settings, presets, and generated bindings remain
  byte-identical unless the acceptance action intentionally changes them.
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
