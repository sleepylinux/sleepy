# Sleepy Linux Desktop Foundation Design

## Status

Approved for implementation planning on 2026-08-23 after two review passes.

## Purpose

Sleepy Linux is an independently branded NixOS-based operating system. Its first milestone is a reliable and maintainable desktop foundation built around Niri and Quickshell. The repository will later grow to include an installer, graphical settings, profiles, release automation, and additional architectures without restructuring the foundation.

The first implementation must provide:

- a bootable `x86_64-linux` NixOS configuration for the Sleepy VM;
- Niri from `nixpkgs` as the Wayland compositor;
- a custom Quickshell panel using the temporary Lunar Minimal design;
- ReGreet on greetd as the graphical login flow;
- Xwayland Satellite and the required desktop portals;
- Firefox from the standard `nixpkgs` package, Ghostty with Fish, and Fuzzel as the temporary launcher;
- both integrated and standalone Home Manager outputs;
- validation that prevents broken Nix, Niri, or Quickshell configuration from becoming an active generation.

## Scope

### Included in the first milestone

- Flake and lock file pinned to `nixos-unstable`.
- Modular NixOS and Home Manager configuration.
- Host definition for the existing Sleepy VM and a parameterized primary user, initially `lazy`.
- Niri session and modular KDL configuration.
- Quickshell service and minimal 52 px left panel.
- Lunar Minimal theme tokens and replaceable branding assets.
- Firefox, Ghostty, Fish, Fuzzel, portals, and only the support packages required for a usable session.
- Sleepy Linux public branding where NixOS permits a safe downstream override.
- Formatting, static checks, builds, and VM smoke-test documentation.
- Git repository on `main`, Conventional Commits, and a future GitHub origin.

### Deferred

- Graphical installer.
- Graphical settings application.
- Application catalogue and profile selection UI.
- Stable release channel and automatic installation of updates.
- Hardware-specific profiles beyond the current VM.
- Final logo and mascot.

The deferred systems receive stable extension points, not placeholder implementations.

## Design principles

1. Each module has one responsibility and an explicit interface.
2. Host-specific data never contains desktop implementation logic.
3. Widgets display state; service objects own system integration.
4. Branding is data, not embedded component logic.
5. Sleepy updates may replace Sleepy-owned code only. User-owned state is never overwritten.
6. Comments explain non-obvious reasons, compatibility constraints, or workarounds. They do not restate readable code.
7. A failed validation or build must leave the active system generation unchanged.
8. The first milestone implements only the functionality required for a usable desktop.

## Repository architecture

```text
.
├── flake.nix
├── flake.lock
├── lib/
│   └── mkSleepyHost.nix
├── hosts/
│   └── sleepy-vm/
│       ├── default.nix
│       └── hardware-configuration.nix
├── profiles/
│   └── desktop.nix
├── packages/
│   ├── sleepy-branding/
│   ├── sleepy-shell/
│   └── default.nix
├── overlays/
│   └── default.nix
├── modules/
│   ├── nixos/
│   │   ├── base/
│   │   ├── branding/
│   │   └── session/
│   ├── home/
│   │   ├── apps/
│   │   ├── niri/
│   │   └── quickshell/
│   └── shared/
│       └── theme/
├── assets/
│   └── branding/
├── checks/
├── docs/
└── local/                 # ignored, machine/user-owned overrides
```

`flake.nix` composes inputs and exports configurations, modules, packages, development shells, formatter, and checks. It does not contain application configuration.

`lib/mkSleepyHost.nix` is the only host factory. It accepts system architecture, host name, primary user, hardware module, and profiles. Adding a machine must not require copying the desktop stack.

`hosts/sleepy-vm` contains only facts and overrides specific to the VM. `profiles/desktop.nix` composes the reusable system and Home Manager modules.

`modules/nixos` owns operating-system services. `modules/home` owns user-session configuration. `modules/shared/theme` exposes stable theme and branding values to consumers without requiring them to know where assets are stored.

`packages` contains independently buildable Sleepy artifacts rather than embedding derivations in modules. The first real packages are the Quickshell configuration and branding assets. `overlays/default.nix` exposes those packages to integrated NixOS and Home Manager configurations through one narrow overlay. Empty placeholders are not committed; each path is introduced with a buildable consumer.

`local/` is outside the public architecture. Public flake outputs do not import it, CI runs without it, and release source or binary artifacts never include it. A developer may explicitly pass local modules to the host factory from an untracked workstation entry point, but no committed module, package, check, or release build may depend on their presence.

## Flake outputs

The flake will export:

- `nixosConfigurations.sleepy-vm` for the current VM;
- `nixosModules.sleepy` as the reusable system module;
- `homeConfigurations` for a standalone `lazy` test deployment;
- `homeManagerModules.sleepy` as the reusable user module;
- `packages.${system}` for independently buildable Sleepy artifacts;
- `devShells.${system}.default` with the formatter, linters, and validation tools;
- `formatter.${system}` using Alejandra;
- `checks.${system}` for evaluation, static analysis, configuration validation, and smoke builds.

The user name is a parameter of the host factory, not a hard-coded dependency inside desktop modules. A central supported-systems list and a `forAllSystems` helper generate every system-indexed output. Milestone 1 includes only `x86_64-linux`, but adding an architecture changes that list rather than the output structure.

A future installer milestone may export an installable ISO through `packages.${system}.sleepy-iso` and its supporting NixOS configuration. The first milestone does not build or publish an ISO.

## System layer

### Base

The base module owns the primary user, networking, locale, keyboard defaults, Fish, and the minimal system services needed by the desktop. The default locale is `en_US.UTF-8`. US and Russian keyboard layouts are available, with `Alt+Shift` as the layout toggle.

### Branding

The public product name is `Sleepy Linux`, the short identifier is `sleepy`, and the initial product version is `0.1.0`. Safe downstream branding will set public release metadata so the system presents itself as Sleepy Linux and declares compatibility through `ID_LIKE=nixos`.

Core Nix/NixOS implementation names, option paths, commands, state-version semantics, and compatibility identifiers remain unchanged where renaming could break tooling. `system.stateVersion` and Home Manager `home.stateVersion` are migration contracts and are never advanced automatically during an update.

The Lunar Minimal logo is temporary. Colors, metrics, logo, and future mascot paths are exposed through a branding interface. Replacing the asset package must not require editing Quickshell widgets.

### Session

greetd starts ReGreet. ReGreet launches the Sleepy Niri session. The session provides Niri, Xwayland Satellite, required XDG portals, clipboard support, notifications, policy authentication, audio integration, and Quickshell startup.

Sleepy uses the packaged upstream `niri-session` and `niri.service` lifecycle instead of duplicating it in a custom wrapper. Niri running with `--session` creates the Wayland and IPC sockets, integrates Xwayland Satellite, sets `WAYLAND_DISPLAY`, `DISPLAY`, `XDG_CURRENT_DESKTOP`, `XDG_SESSION_TYPE`, and `NIRI_SOCKET`, and imports the resulting environment into the systemd user manager and D-Bus activation environment before declaring the compositor ready. The upstream service orders `graphical-session.target` after compositor readiness, and `niri-session` drives its shutdown path when Niri exits. Sleepy desktop services bind to that target using `PartOf`, `After`, and `Requisite` as appropriate.

This behavior is an explicit integration contract and receives an acceptance test. Sleepy may package narrowly scoped upstream-compatible unit overrides if a pinned Niri release requires a shutdown fix, but it does not maintain a parallel session implementation.

Implementation follows the pinned versions of upstream [`niri-session`](https://github.com/niri-wm/niri/blob/main/resources/niri-session), [`niri.service`](https://github.com/niri-wm/niri/blob/main/resources/niri.service), and Niri's documented Xwayland Satellite integration rather than copying their current contents.

The selected Niri and Xwayland Satellite packages must provide top-level KDL includes and Niri-managed Xwayland integration. The implementation plan must verify these capabilities against the pinned packages: validate a generated configuration that contains includes, then run the X11 acceptance test without a separately managed Satellite service. The design does not encode release numbers as capability proxies.

Niri configuration is split into focused KDL files for input, outputs, appearance, key bindings, window rules, and startup. The generated top-level configuration only includes these files. All KDL files are generated and read-only. The future Settings GUI never edits them. Supported runtime changes are stored in the Sleepy settings backend and applied through an integration service or Niri IPC; immutable KDL remains the fallback source of defaults.

The key binding `Mod+T` launches Ghostty inside the guest. In virtualized use, the host may intercept the Super key before the guest receives it; the VM documentation will include the virt-manager keyboard-grab procedure and an alternate guest binding for recovery.

## Home Manager layer

The same Home Manager module supports two modes:

1. integrated into `nixosConfigurations.sleepy-vm`;
2. standalone through `homeConfigurations` for development and testing.

Both modes consume the same module implementation and theme interface. Mode-specific glue is kept at the flake output boundary.

### Applications

- Firefox is provided by the standard `nixpkgs` Firefox package.
- Ghostty is the default terminal and starts Fish.
- Fish initially uses its standard prompt.
- Fuzzel is a temporary application launcher.

The base profile does not include a broad application bundle. Future application installation uses a dedicated user-owned Nix profile rather than editing the Sleepy base profile or Home Manager package list. Sleepy-managed base packages and installer-managed applications have separate ownership metadata; the installer refuses or explains duplicates instead of silently claiming a base package.

Before installer implementation begins, its design must define one canonical profile name and filesystem path shared by install, update, list, repair, and uninstall operations. Milestone 1 deliberately does not choose that path because it does not create or mutate the installer profile.

## Quickshell architecture

The Quickshell configuration is split by responsibility:

```text
quickshell/
├── shell.qml
├── Theme.qml
├── services/
├── modules/
│   └── panel/
└── widgets/
```

`shell.qml` composes top-level modules. `services` adapts Niri, systemd, network, audio, power, tray, and clock state. Widgets receive simple properties and actions and contain no process invocation or system parsing.

The MVP panel is permanently visible on the left edge and is 52 px wide. It contains:

- the temporary Lunar Minimal mark at the top;
- Niri workspaces below it;
- tray and status indicators in the middle;
- clock and user/power entry at the bottom.

The panel starts as a Home Manager systemd user service tied to `graphical-session.target`. A Quickshell crash is restarted with rate limiting; it does not terminate Niri or user applications. After a bounded number of consecutive failures, systemd stops restarting Quickshell and records the failure. Niri remains fully operable through built-in key bindings for Ghostty, Fuzzel, session logout, and essential window and workspace actions. The panel is never the only route to launch or exit the session.

## User state and update safety

Sleepy-owned code and user-owned state are separate by construction.

### Ownership boundaries

- The Git repository and Nix store contain versioned Sleepy modules, defaults, schemas, and assets.
- `local/` contains machine or administrator overrides and is ignored by Git.
- Mutable desktop preferences live under the user's XDG configuration directory, outside generated Home Manager source files.
- Packages installed by the future application installer live in a dedicated user-owned Nix profile, separate from system packages and Home Manager packages.
- Arbitrary files and packages created through normal user tools are outside the Sleepy update target.
- Credentials and secrets are never stored unencrypted in the repository or Nix store. A later security milestone may integrate `sops-nix` or `agenix` without changing this ownership rule.

An updater must never run a destructive repository reset over local configuration, replace an existing unmanaged file with `force = true`, or rewrite the user's home directory from defaults.

### Activation behavior

- Home Manager owns only files explicitly declared as managed.
- If an unmanaged file blocks a managed target, activation fails safely and reports the conflict instead of overwriting it.
- Local overrides are imported only when present and must expose a documented module interface.
- Updating the Sleepy flake or lock file changes the versioned distribution layer only.
- Existing user settings are read after defaults and therefore take precedence within the supported schema.

### Runtime settings and migrations

The settings model has one direction of ownership:

```text
Nix and Home Manager
        ↓ immutable defaults and schema
~/.config/sleepy/settings.json
        ↓ mutable user overrides
Quickshell services and Niri integration
```

Home Manager may install the schema and a default document in the Nix store, but it never manages or rewrites `~/.config/sleepy/settings.json`. The runtime creates that file only when the user first changes a setting. The effective value is the validated user override when present and the immutable default otherwise. Rebuilding Home Manager cannot revert a mutable preference.

The future settings backend uses this versioned JSON document in the user's XDG configuration directory. Writes are atomic. Before a schema migration, Sleepy creates a timestamped backup. Migration validates the new document before replacing the old one. If validation fails, the old settings remain active and the failure is reported.

Unknown or newly removed keys do not crash the shell. They are preserved where possible and ignored with a diagnostic until an explicit migration handles them. Corrupt settings fall back to safe defaults while the original file is retained for recovery.

These guarantees apply to future update tooling and are part of its acceptance criteria, even though the updater itself is outside the first milestone.

## Session data flow

1. Nix builds packages, services, immutable defaults, validation schemas, and asset paths.
2. greetd authenticates the user and starts the Niri session.
3. `niri-session` starts the upstream `niri.service` and waits for it.
4. Niri creates its Wayland socket, integrates Xwayland Satellite, and imports the completed environment into systemd and D-Bus.
5. Niri declares readiness and systemd reaches `graphical-session.target`.
6. systemd starts Quickshell and other Sleepy services bound to that target.
7. Quickshell service objects observe system state and expose typed properties and actions.
8. Widgets render the service state and invoke only those actions.
9. Mutable user settings overlay immutable defaults without changing generated files or KDL.

## Failure handling and recovery

- Nix evaluation or build failure prevents activation.
- Invalid Niri KDL prevents the configuration from passing checks.
- Invalid QML prevents the configuration from passing checks.
- A Quickshell runtime crash triggers a rate-limited systemd user restart up to the configured failure threshold; Niri keyboard controls remain available after the threshold is reached.
- A Niri crash ends the session and returns the user to ReGreet; logs remain in the journal.
- Ending Niri drives the upstream shutdown target, stops `graphical-session.target`, and stops all Sleepy services bound to it.
- Boot retains previous NixOS generations so the user can select a known-good system.
- A settings migration failure retains the original settings and activates safe defaults.
- Host keyboard capture issues are documented separately from guest compositor failures.

## Code quality policy

- Prefer focused modules and descriptive names over comments.
- Split a file when it acquires more than one reason to change.
- Comments are allowed for compatibility constraints, workarounds, security reasoning, and non-obvious design choices.
- Do not add headings, narrations, or comments that merely repeat the next expression.
- Keep public module options documented at their boundary.
- Avoid hidden global state and implicit imports.
- Do not add abstraction until at least one real consumer requires the boundary, except for the explicitly planned branding and settings contracts.

## Validation and testing

`flake check` is the common local and CI entry point. CI separates fast evaluation from expensive builds. It will include, directly or through scripts:

- Alejandra formatting verification;
- statix and deadnix;
- ShellCheck when shell scripts are present;
- NixOS and standalone Home Manager evaluation;
- a smoke build of the Sleepy VM system closure;
- Niri configuration validation;
- QML linting for Quickshell;
- a repository-clean assertion after generators and checks, including failure on unexpected generated or untracked files.

The fast CI stage runs `nix flake check --no-build`. A separate stage realizes the required system and Home Manager derivations. A later milestone replaces part of the manual smoke coverage with a NixOS VM test that boots, reaches greetd, authenticates a test user, and asserts that Niri and Quickshell run. Firefox launch becomes part of that test when the graphical test environment is reliable.

The manual VM acceptance check verifies:

1. ReGreet appears and accepts login.
2. The Sleepy Niri session starts without a fallback desktop.
3. The 52 px Quickshell panel appears and restarts independently after termination.
4. `Mod+T` opens Ghostty after virt-manager has captured the keyboard.
5. Firefox starts and portals provide expected file/open behavior.
6. An X11 test application starts through Xwayland Satellite.
7. US/RU layout switching works.
8. A previous generation remains bootable after a deliberately failed candidate build.
9. Repeatedly crashing Quickshell reaches its restart limit while Ghostty, Fuzzel, and logout remain accessible through Niri key bindings.
10. Ending Niri follows the upstream shutdown path and stops `graphical-session.target` and its bound user services.

CI will run on feature branches and pull requests. A weekly automation may propose flake input updates, but merging remains manual after CI and a VM test.

## Version control and releases

- The initial branch is `main`.
- Development uses feature branches and pull requests.
- Commits follow Conventional Commits.
- Releases use SemVer, beginning with `v0.1.0`.
- The project is released under `GPL-3.0-only`.
- The GitHub `origin` will be added when its URL is provided.

The first commit contains the approved design and repository hygiene rules. Implementation begins only after this specification is reviewed and the implementation plan is approved.

## Acceptance criteria

The desktop foundation is complete when:

- a fresh build of `nixosConfigurations.sleepy-vm` succeeds;
- the same Home Manager desktop layer evaluates standalone;
- the full manual VM acceptance check passes;
- public release metadata identifies Sleepy Linux without breaking NixOS tooling;
- replacing branding assets requires no widget changes;
- a failed build or runtime shell crash has the documented recovery path;
- an update test proves that local overrides, mutable user preferences, user-installed packages, and unrelated home files remain unchanged;
- a fresh clone with no `local/` directory reproducibly builds `nixosConfigurations.sleepy-vm` from the committed flake and lock file;
- rebuilding Home Manager does not create, rewrite, or delete `~/.config/sleepy/settings.json`;
- the system remains operable from Niri key bindings when Quickshell is unavailable;
- the systemd user environment receives the Wayland variables and tears down with the Niri session;
- no unencrypted secret enters the repository or Nix store through a supported configuration path.
