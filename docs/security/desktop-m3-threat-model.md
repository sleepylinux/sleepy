# Desktop M3 Threat Model

## Protected assets

- User settings, presets, bindings, themes, notification history, launcher
  metrics, provider configuration, and overrides.
- Integrity and ordering of system snapshots, mutations, and Niri commands.
- User-session availability when one hardware or network backend fails.
- Secrets outside the repository and outside diagnostic payloads.

## Trust boundaries

- The session socket accepts only the owning UID and strict SDK documents.
- D-Bus and subprocess output are untrusted and parsed with size and time
  bounds before becoming typed state.
- Desktop Entry, ICS, weather, geocoding, wallpaper, theme, notification, and
  fixture input are untrusted data.
- Nix store inputs are immutable but must match exact reviewed revisions.

## Required mitigations

- Deny unknown fields and versions; never convert parse failure into success.
- Execute only fixed programs with argv arrays. Desktop Entry field expansion
  produces argv and never invokes a shell.
- Reject stale generations and require confirmed mutation readback.
- Kill, wait, and join every timed-out or cancelled child process.
- Validate writable roots through retained directory descriptors; reject
  symlink traversal and non-owned or over-permissive state.
- Publish durable changes through exclusive same-directory temporaries,
  fsync, atomic rename, directory fsync, and reconciled journals.
- Render notification and calendar text as plain text; constrain decoded input
  size, recurrence windows, images, and network responses.
- Redact paths, SSIDs, notification content, calendar text, and device names
  from public evidence unless fixtures intentionally provide them.
- Do not run destructive session actions, disk operations, installation, or
  physical-hardware tests during M3 automation.

## Failure policy

Capability failures are local. The daemon retains the last valid value with a
typed diagnostic where safe, or marks only that capability unavailable. A
mutation whose commit cannot be proven reports unknown state and never success.
Malformed durable input remains byte-identical and the last valid theme or
generated binding stays active.

