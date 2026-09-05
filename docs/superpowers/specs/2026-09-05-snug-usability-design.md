# Snug and Sleepy usability design

User decisions: CLI only, short operation flags (especially `snug -i vim`),
rolling releases, general hardware including NVIDIA. Existing root worktree
is the implementation workspace. This implements the user's requested work;
no live system deployment or physical disk mutation is part of development.

## Additional user requirements

Ship a minimal bootable ISO with a polished terminal onboarding flow and package
categories for development, games and everyday applications. Detect hardware
and offer explicit driver choices. `snug -it vim` is the temporary installation
form, with `--install --temporary` equivalent. Provide built-in help, full Nix
passthrough and a permanent English command reference. All docs/UI are English.

## Snug

Python standard library CLI, Nix backend, a dedicated user profile at
`${XDG_STATE_HOME:-$HOME/.local/state}/snug/profile`. No shell evaluation of
arguments, no sudo for personal packages, no automatic generation deletion.
`-i/install`, `-r/remove`, `-s/search`, `-l/list`, `-u/update`,
`-b/rollback`, `-x/run`, `-e/shell`, `-d/dev`, `--doctor/doctor`.
`-u --system` updates the OS; `-b --system` rolls back the system generation.
`-u` updates all snug-owned personal packages. A separate system flag avoids
unexpected privilege escalation for an application update.

Default app source: `github:NixOS/nixpkgs/nixos-unstable`. Persist origin references
through Nix profiles so update can resolve newer versions. Configure command
and desktop search paths for the dedicated profile. Mutations take a per-user
lock; Nix supplies atomic generation changes. CLI preserves backend exit codes.
A failed network/build operation must not print success or erase old state.

`snug -d init python|node|rust [directory]` creates a non-overwriting project
flake, generates its lock with Nix, and explains how to enter. `snug -d` enters
an existing flake via `nix develop`; `snug -d update` explicitly updates it.
`snug -e package...` provides temporary packages, with `-- command args` optional.

System update source is a user-editable host flake, configured through
`/etc/snug/system.json` (path and host). It owns machine-specific configuration
and follows `github:sleepylinux/sleepy` via a `sleepy` input. Update only that
input in a private copy, including its pinned dependency graph, build before
activation, retain the previous generation. Reject unsafe source ownership
and ambiguous host configuration; require admin authentication for activation.
No arbitrary user-controlled executable is run through elevated PATH. This is
rolling Sleepy main, not independent unreviewed updates of each component SHA.
Existing developer VM can be configured explicitly and the doctor should
explain missing system update setup.

## Desktop fixes

Enable Nix flakes, file manager and removable media support; add volume/mute/
brightness keys using packaged tools. Keep lock and sleep under existing session
ownership. Update recovery instructions for Hyprland units. Do not claim hardware
or full visual acceptance based on configuration or source checks.

## Installation and hardware

Provide a reusable host flake template, documented NixOS installation path and
opt-in GPU configuration for Intel/AMD/NVIDIA including hybrid bus IDs. Keep
VM-specific UUIDs, username and rendering workarounds isolated. Existing manual
installation uses nixos-generate-config and nixos-install; never select or wipe
a disk automatically. A GUI installer is not required by the user.

## Validation

Use unit/subprocess tests for argument handling, failure propagation, state
preservation, no-overwrite dev init and update ordering. Real Nix tests use
isolated HOME/profile/project data. Evaluate new NixOS configuration assertions,
run existing root fixtures and formatting, build snug and relevant checks.
Report exact limits of full system/VM/hardware tests separately.
