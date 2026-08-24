# Sleepy Desktop Milestone 3 Design

## Status and goal

Approved on 2026-08-24 after the M2 Control Center design. M3 turns the
accepted M2 shell into a daily desktop without adding an installer, disk
operations, hardware-specific workarounds, or destructive acceptance tests.

The implementation spans the public SDK, session service, artwork, desktop,
and root integration repositories. Every component remains independently
testable and exports its own flake checks.

## Runtime architecture

`sleepy-sessiond` is the single user-session state authority. Independent
adapter actors observe NetworkManager, BlueZ, UPower, power profiles, MPRIS,
PipeWire, backlight, night light, and Niri. An adapter failure changes only its
typed capability state. It never prevents healthy adapters from publishing.

Clients connect through the mode-0600 Unix socket
`$XDG_RUNTIME_DIR/sleepy/session.sock`; the server verifies the peer UID.
`sleepyctl events watch --format ndjson` is the Quickshell bridge. Every new
subscriber receives a strict full snapshot before incremental events.

Wire v2 separates the UUID client `requestId` from the daemon-owned monotonic
`generation`. The daemon durably reserves generation blocks so restart may
create gaps but never reuse an identifier. A mutation is successful only after
fixed-argv execution, bounded readback, state publication, and an exact
generation match. The UI may show pending state but never an optimistic value.

Every owned subprocess has a deadline and cancellation path that performs
kill, wait, and reader-task join. No user string is evaluated by a shell.

## Daily desktop capabilities

The daemon owns `org.freedesktop.Notifications`, safe plain-text history,
unread state, actions, DND, application grouping, and urgency. The active view
contains 500 entries; older or dismissed entries move atomically to a durable
archive. Only an explicit purge deletes archived notification data. Actions
whose originating D-Bus client disappeared are marked expired.

OSD queues are per output. One item is visible at a time, updates of the same
kind coalesce, and other items remain FIFO. Volume, microphone, brightness,
media, and power-profile events route through fresh Niri focused-output state.

The launcher indexes XDG Desktop Entries with normal override precedence and
honors visibility and `TryExec` fields. `Exec` is parsed into argv using the
freedesktop field codes; arbitrary user text is never executable. Recent and
frequent ranking lives in private XDG state. Overview focus, close, and
workspace actions are typed Niri commands confirmed by later events.

Calendar is a replaceable local ICS provider. Weather uses replaceable MET.no
and Nominatim providers with explicit submit, attribution, caching, bounded
network requests, and no repository secrets. System widgets consume the
shared event snapshot rather than starting QML probes.

Themes use immutable built-ins and copy-on-write user documents. Preview is
memory-only. Apply and rollback are journaled and generation-confirmed.
Malformed input preserves the last valid theme. All surfaces share one effects
policy for full, reduced, none, reduced-motion, and opaque modes. Semantic
colors meet WCAG AA: 4.5:1 for normal text and 3:1 for large text and controls.

## Future boundaries

The SDK defines strict versioned installation/profile manifests, a declarative
machine profile, a first-boot state machine, and generation/rollback provider
interfaces. M3 ships only a fake installer provider. These APIs cannot modify
disks, users, networking, or the system.

Hardware contracts include typed device identifiers, capability snapshots,
recorded fixture replay, explicit unavailable/unsupported/permissionDenied/
timeout/parse/error states, and future lab-report hooks. Production absence
disables only the corresponding control.

## Persistence and compatibility

M2 settings, presets, generated bindings, and overrides are never rewritten
at startup. New durable documents use separate XDG config/state paths; HTTP
bodies use XDG cache. Writable paths retain the M2 descriptor-relative,
no-follow, exclusive-temporary, atomic-rename, file-fsync, directory-fsync,
journal, and startup-reconciliation rules.

M2 `sleepyctl system show/set --generation` commands remain deprecated shims
for one release. New clients use request IDs and server generations. Unknown
wire or durable schema versions fail closed without changing bytes.

## Delivery and acceptance

Component branches are `feat/desktop-m3-contracts`,
`feat/desktop-m3-event-service`, `feat/desktop-m3-icons`, and
`feat/desktop-m3-daily-shell`. The root branch is
`feat/desktop-m3-integration`. Component PRs merge before the root pins exact
reviewed public revisions.

Acceptance requires Rust debug/release checks, software and Vulkan RHI QML
tests, deterministic two-output screenshots, Niri 26.04 validation, x86_64
flake checks, aarch64 evaluation, pristine first login, and QEMU M2-to-M3
byte-preservation. Logout, reboot, and power-off use fake providers in tests.

