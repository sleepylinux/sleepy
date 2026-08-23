# Sleepy Linux Desktop Foundation Design

## Status

Approved for implementation planning on 2026-08-23.

## Purpose

Sleepy Linux is an independently branded NixOS-based operating system. Its first milestone is a reliable and maintainable desktop foundation built around Niri and Quickshell. The repository will later grow to include an installer, graphical settings, profiles, release automation, and additional architectures without restructuring the foundation.

The first implementation must provide:

- a bootable `x86_64-linux` NixOS configuration for the Sleepy VM;
- Niri from `nixpkgs` as the Wayland compositor;
- a custom Quickshell panel using the temporary Lunar Minimal design;
- ReGreet on greetd as the graphical login flow;
- Xwayland Satellite and the required desktop portals;
- official Firefox, Ghostty with Fish, and Fuzzel as the temporary launcher;
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

`flake.nix` composes inputs and exports configurations, modules, formatter, and checks. It does not contain application configuration.

`lib/mkSleepyHost.nix` is the only host factory. It accepts system architecture, host name, primary user, hardware module, and profiles. Adding a machine must not require copying the desktop stack.

`hosts/sleepy-vm` contains only facts and overrides specific to the VM. `profiles/desktop.nix` composes the reusable system and Home Manager modules.

`modules/nixos` owns operating-system services. `modules/home` owns user-session configuration. `modules/shared/theme` exposes stable theme and branding values to consumers without requiring them to know where assets are stored.

## Flake outputs

The flake will export:

- `nixosConfigurations.sleepy-vm` for the current VM;
- `nixosModules.sleepy` as the reusable system module;
- `homeConfigurations` for a standalone `lazy` test deployment;
- `homeManagerModules.sleepy` as the reusable user module;
- `formatter.x86_64-linux` using Alejandra;
- `checks.x86_64-linux` for evaluation, static analysis, configuration validation, and smoke builds.

The user name is a parameter of the host factory, not a hard-coded dependency inside desktop modules.

## System layer

### Base

The base module owns the primary user, networking, locale, keyboard defaults, Fish, and the minimal system services needed by the desktop. The default locale is `en_US.UTF-8`. US and Russian keyboard layouts are available, with `Alt+Shift` as the layout toggle.

### Branding

The public product name is `Sleepy Linux`, the short identifier is `sleepy`, and the initial product version is `0.1.0`. Safe downstream branding will set public release metadata so the system presents itself as Sleepy Linux and declares compatibility through `ID_LIKE=nixos`.

Core Nix/NixOS implementation names, option paths, commands, state-version semantics, and compatibility identifiers remain unchanged where renaming could break tooling. `system.stateVersion` and Home Manager `home.stateVersion` are migration contracts and are never advanced automatically during an update.

The Lunar Minimal logo is temporary. Colors, metrics, logo, and future mascot paths are exposed through a branding interface. Replacing the asset package must not require editing Quickshell widgets.

### Session

greetd starts ReGreet. ReGreet launches the Sleepy Niri session. The session provides Niri, Xwayland Satellite, required XDG portals, clipboard support, notifications, policy authentication, audio integration, and Quickshell startup.

Niri configuration is split into focused KDL files for input, outputs, appearance, key bindings, window rules, and startup. The generated top-level configuration only includes these files.

The key binding `Mod+T` launches Ghostty inside the guest. In virtualized use, the host may intercept the Super key before the guest receives it; the VM documentation will include the virt-manager keyboard-grab procedure and an alternate guest binding for recovery.

## Home Manager layer

The same Home Manager module supports two modes:

1. integrated into `nixosConfigurations.sleepy-vm`;
2. standalone through `homeConfigurations` for development and testing.

Both modes consume the same module implementation and theme interface. Mode-specific glue is kept at the flake output boundary.

### Applications

- Firefox is the official build from `nixpkgs`.
- Ghostty is the default terminal and starts Fish.
- Fish initially uses its standard prompt.
- Fuzzel is a temporary application launcher.

The base profile does not include a broad application bundle. Future application installation must use a user-owned package layer rather than editing the Sleepy base profile.

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

The panel starts as a Home Manager systemd user service tied to the graphical session. A Quickshell crash is restarted with rate limiting; it does not terminate Niri or user applications.

## User state and update safety

Sleepy-owned code and user-owned state are separate by construction.

### Ownership boundaries

- The Git repository and Nix store contain versioned Sleepy modules, defaults, schemas, and assets.
- `local/` contains machine or administrator overrides and is ignored by Git.
- Mutable desktop preferences live under the user's XDG configuration directory, outside generated Home Manager source files.
- Packages installed by the future application installer live in a separate user-owned package/profile layer.
- Arbitrary files and packages created through normal user tools are outside the Sleepy update target.

An updater must never run a destructive repository reset over local configuration, replace an existing unmanaged file with `force = true`, or rewrite the user's home directory from defaults.

### Activation behavior

- Home Manager owns only files explicitly declared as managed.
- If an unmanaged file blocks a managed target, activation fails safely and reports the conflict instead of overwriting it.
- Local overrides are imported only when present and must expose a documented module interface.
- Updating the Sleepy flake or lock file changes the versioned distribution layer only.
- Existing user settings are read after defaults and therefore take precedence within the supported schema.

### Runtime settings and migrations

The future settings backend uses a versioned JSON document in the user's XDG configuration directory. Writes are atomic. Before a schema migration, Sleepy creates a timestamped backup. Migration validates the new document before replacing the old one. If validation fails, the old settings remain active and the failure is reported.

Unknown or newly removed keys do not crash the shell. They are preserved where possible and ignored with a diagnostic until an explicit migration handles them. Corrupt settings fall back to safe defaults while the original file is retained for recovery.

These guarantees apply to future update tooling and are part of its acceptance criteria, even though the updater itself is outside the first milestone.

## Session data flow

1. Nix builds packages, services, immutable defaults, validation schemas, and asset paths.
2. greetd authenticates the user and starts the Niri session.
3. Niri starts the graphical-session target.
4. systemd starts Quickshell for that target.
5. Quickshell service objects observe system state and expose typed properties and actions.
6. Widgets render the service state and invoke only those actions.
7. Future mutable user settings overlay immutable defaults without changing generated files.

## Failure handling and recovery

- Nix evaluation or build failure prevents activation.
- Invalid Niri KDL prevents the configuration from passing checks.
- Invalid QML prevents the configuration from passing checks.
- A Quickshell runtime crash triggers a rate-limited systemd user restart.
- A Niri crash ends the session and returns the user to ReGreet; logs remain in the journal.
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

`flake check` is the common local and CI entry point. It will include, directly or through scripts:

- Alejandra formatting verification;
- statix and deadnix;
- NixOS and standalone Home Manager evaluation;
- a smoke build of the Sleepy VM system closure;
- Niri configuration validation;
- QML linting for Quickshell.

The manual VM acceptance check verifies:

1. ReGreet appears and accepts login.
2. The Sleepy Niri session starts without a fallback desktop.
3. The 52 px Quickshell panel appears and restarts independently after termination.
4. `Mod+T` opens Ghostty after virt-manager has captured the keyboard.
5. Firefox starts and portals provide expected file/open behavior.
6. An X11 test application starts through Xwayland Satellite.
7. US/RU layout switching works.
8. A previous generation remains bootable after a deliberately failed candidate build.

CI will run on feature branches and pull requests. A weekly automation may propose flake input updates, but merging remains manual after CI and a VM test.

## Version control and releases

- The initial branch is `main`.
- Development uses feature branches and pull requests.
- Commits follow Conventional Commits.
- Releases use SemVer, beginning with `v0.1.0`.
- The project is intended for public release under `GPL-3.0-or-later`.
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
- an update test proves that local overrides, mutable user preferences, user-installed packages, and unrelated home files remain unchanged.
