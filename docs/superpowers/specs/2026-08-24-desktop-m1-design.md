# Sleepy Desktop Milestone 1 Design

## Status

Approved in conversation on 2026-08-24.

## Goal

Deliver the first end-to-end vertical slice of the Sleepy desktop: stable public
contracts, a user-owned settings and preset store, a polished left inset rail
with a quick-settings drawer, and integration through the Sleepy distribution
flake.

This milestone intentionally proves boundaries before implementing the full
control center, plugin runtime, notification center, Overview, AI agent,
installer, or release infrastructure.

## Repositories

- `sleepy-sdk` owns versioned JSON schemas, Rust contract types, fixtures, and
  validation helpers.
- `sleepy-session` owns the Rust settings/preset store and `sleepyctl` command
  line interface. D-Bus transport is deferred until the store contract is
  proven; its public service name remains reserved as `org.sleepy.Session1`.
- `sleepy-desktop` owns the Quickshell UI package, shared design tokens, panel,
  quick-settings drawer, and a local preview harness.
- `sleepy-artwork` owns the lunar mark and its asset manifest.
- `sleepy` pins and composes the component repositories. During local
  development it may use explicit path overrides; release configuration must
  use locked Git inputs.

## Contract model

All documents use `schemaVersion: 1`. Unknown keys are rejected at this stage so
that accidental misspellings fail visibly. Future migrations must explicitly
preserve keys they understand before the schema is relaxed.

`SettingsDocument` contains the active preset identifier, appearance mode,
palette source, reduced-motion preference, effects profile, panel visibility,
and web-search preference. It never contains credentials or mutable shell
layout.

`PresetDocument` contains a stable identifier, user-facing name, origin,
optional base preset, layouts keyed by display identity, drawers, keybindings,
and plugin requirements. The first slice implements a left inset rail and one
left quick-settings drawer while keeping the schema extensible to additional
surfaces.

`PluginManifest` defines identity, semantic version, API version, QML entrypoint,
supported surface kinds, requested capabilities, and an optional settings
schema. Loading third-party QML remains deferred.

The canonical built-in preset identifier is `builtin.sleepy`. User presets use
UUID identifiers. Built-in presets are immutable. Editing a built-in preset
creates a user-owned copy.

## Settings and preset ownership

The default settings document and built-in presets are immutable inputs. User
state lives below XDG paths supplied to `sleepy-session`; tests always use an
isolated temporary directory.

Writes use a same-directory temporary file, file sync, atomic rename, and parent
directory sync. A document is validated before it becomes visible. Failed
validation or I/O leaves the previous file unchanged.

The store supports:

- initialize defaults without overwriting existing state;
- list built-in and user presets;
- create, duplicate, and rename user presets;
- reject direct mutation of built-in presets;
- atomically select an active preset;
- load the last valid state after a failed candidate write.

The first `sleepyctl` surface exposes `settings show`, `presets list`,
`presets duplicate`, `presets rename`, and `presets activate`. Output is JSON so
the desktop client and future D-Bus layer share one observable contract.

## Desktop composition

The default shell uses a permanently visible left inset rail. Geometry follows
a 12 px rhythm, with 22 px outer radii and 16 px inner radii. The dark default
uses matte, opaque-enough surfaces and lavender accents; reduced motion disables
non-essential transitions.

The rail contains the lunar mark, dynamic Niri workspaces, and bottom status
items. Activating the status item opens one left quick-settings drawer aligned
to the rail. The drawer provides visual states for network, Bluetooth, night
light, focus mode, volume, and brightness. System mutations remain disabled in
this slice unless a real service adapter reports support.

Widgets render typed properties and actions. Process execution and parsing stay
inside services. The shell must still operate when `sleepy-session` is absent by
loading immutable defaults and exposing a visible diagnostic in logs.

## Branding

The current crescent concept remains, but the asset package adds a manifest with
stable logical names. The desktop consumes the logical primary mark through its
package input rather than embedding an asset path in widgets.

## Validation

- Contract fixtures must demonstrate both acceptance and rejection.
- Store tests must prove non-overwrite, atomic failure behavior, built-in preset
  immutability, duplication, rename, and activation.
- QML must pass `qmllint`; pure geometry and token contracts receive runnable
  tests rather than source-text assertions.
- Each component must build independently before distribution integration.
- The root flake must keep the existing VM configuration and checks, expose the
  component packages, and pass full `nix flake check` in CI or the Sleepy VM.

