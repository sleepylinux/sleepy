# Snug and Sleepy usability implementation plan

> Execute in the existing isolated worktree. Use subagent-driven-development
> for bounded independent desktop/hardware work and review; controller owns snug.

**Goal:** Ship short-flag snug CLI, rolling updates, dev shells, and fix core usability gaps.
**Architecture:** Python CLI delegates immutable builds and profile generations to Nix. NixOS modules integrate packages and paths. Host templates preserve hardware ownership.
**Tech Stack:** Python 3 standard library, Nix flakes, NixOS, Home Manager.
**Spec:** `docs/superpowers/specs/2026-09-05-snug-usability-design.md`.

## Global constraints

No host activation, writes to non-disposable disks, automatic GC, profile
takeover, or claims of universal hardware verification. Installation and real
activation tests run only on explicitly created disposable VM disks. Preserve
user configuration and remove created test resources after evidence is saved.

## Tasks

- [x] CLI package lifecycle: create `packages/snug/snug.py`, package derivation,
  and `checks/snug-test.py`. Verify short flags, no shell expansion, backend
  failures, profile isolation, lock behavior, list/remove and update/rollback.
- [x] CLI development environments: `packages/snug/devenv.py`; verify presets,
  no overwriting existing files, lock generation failure cleanup and entry.
- [x] Rolling system updates: `packages/snug/system_update.py`; root-owned config and
  staging, candidate build before switch, rollback and failure tests.
- [x] Desktop usability: Nix experimental features, Thunar/GVfs/UDisks,
  volume/mute/brightness bindings, evaluated contracts and documentation.
- [x] Generic host template and hardware module: installation documentation,
  declarative GPU variants, preserve VM defaults, evaluated checks.
- [x] Integrate snug overlay/package/check exports and profile paths. Run
  `python3 checks/snug-test.py`, real Nix lifecycle checks, root fixtures,
  `nix flake check --no-build --no-write-lock-file`, formatter and relevant builds.
- [x] Review diff, resolve findings, update audit with completed and remaining gates.

- [x] Minimal bootable ISO module and terminal installer with package categories, preflight configuration evaluation, persistent boot targets and credential setup.
- [x] Build and boot the final ISO; record exact evidence and unresolved hardware limits.

Exact produced-image source, checksum and verification evidence are recorded
in BUILD.md and SHA256SUMS alongside the ISO outside the source checkout.
