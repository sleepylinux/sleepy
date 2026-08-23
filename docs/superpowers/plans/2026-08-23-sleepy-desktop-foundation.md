# Sleepy Linux Desktop Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Sleepy Linux desktop foundation for the existing libvirt VM with Niri, a custom Quickshell panel, ReGreet, Firefox, Ghostty, Fish, and safe Home Manager ownership boundaries.

**Architecture:** A flake composes a parameterized NixOS host factory, reusable NixOS and Home Manager modules, and independently buildable Sleepy packages. Nix and Home Manager own immutable defaults and generated configuration; mutable user state remains outside their file targets. Niri owns the graphical session lifecycle, while Quickshell runs as a rate-limited systemd user service bound to `graphical-session.target`.

**Tech Stack:** Nix flakes, NixOS unstable, Home Manager, Niri/KDL, Quickshell/QML, systemd user services, greetd/ReGreet, Xwayland Satellite, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-23-sleepy-desktop-foundation-design.md`

## Global Constraints

- Public product name: `Sleepy Linux`; short identifier: `sleepy`; initial product version: `0.1.0`.
- Initial platform: `x86_64-linux`; all system-indexed outputs use one `forAllSystems` helper.
- Primary test user: `lazy`; the user remains a host-factory parameter.
- Desktop: Niri from the pinned `nixpkgs`, Quickshell, ReGreet/greetd, and Xwayland Satellite.
- Default applications: standard `nixpkgs` Firefox, Ghostty with Fish, and Fuzzel.
- Default locale: `en_US.UTF-8`; keyboard layouts: `us,ru`; toggle: `Alt+Shift`.
- Panel: always-visible left edge, exactly 52 px, Lunar Minimal temporary branding.
- `system.stateVersion` must match the value already installed in the Sleepy VM; the new Home Manager configuration starts at `home.stateVersion = "26.05"` and never advances automatically.
- `local/`, `secrets/`, mutable settings, and user-installed application profiles are absent from CI and release artifacts.
- Home Manager must never create, replace, or delete `~/.config/sleepy/settings.json`.
- Niri KDL is generated and read-only; future settings tools do not edit it.
- Secrets are never stored unencrypted in Git or the Nix store.
- Comments explain only non-obvious constraints, compatibility behavior, or workarounds.
- Every task ends in a Conventional Commit and leaves `git status --short` empty.

## File Map

| Path | Responsibility |
|---|---|
| `flake.nix` | Inputs and public flake outputs only. |
| `lib/for-all-systems.nix` | Generate system-indexed attributes from one supported-systems list. |
| `lib/mkSleepyHost.nix` | Construct a NixOS host from explicit architecture, host, user, hardware, and module inputs. |
| `hosts/sleepy-vm/` | Existing VM facts, preserved state version, and generated hardware configuration. |
| `profiles/desktop.nix` | Compose reusable NixOS and Home Manager desktop modules. |
| `modules/nixos/base/` | User, locale, networking, audio, and minimal desktop support services. |
| `modules/nixos/branding/` | Safe downstream `os-release` branding. |
| `modules/nixos/session/` | Niri, ReGreet/greetd, portals, Xwayland Satellite, and policy agent. |
| `modules/home/apps/` | Firefox, Ghostty, Fish, Fuzzel, and support utilities. |
| `modules/home/niri/` | Install generated modular KDL and preserve emergency key bindings. |
| `modules/home/quickshell/` | Install the shell package and harden its systemd service. |
| `packages/sleepy-branding/` | Replaceable Lunar Minimal asset package. |
| `packages/sleepy-shell/` | Quickshell source, immutable defaults, and settings schema. |
| `overlays/default.nix` | Expose Sleepy packages through a single narrow overlay. |
| `checks/` | Source contracts, Niri validation, QML lint wrapper, and update-safety checks. |
| `.github/workflows/check.yml` | Fast evaluation and full build CI stages. |
| `docs/` | VM baseline, recovery, deployment, and acceptance instructions. |

---

### Task 1: Capture the Existing VM Contract

**Files:**
- Create: `hosts/sleepy-vm/hardware-configuration.nix`
- Create: `hosts/sleepy-vm/baseline.nix`
- Create: `docs/vm-baseline.md`

**Interfaces:**
- Consumes: the installed Sleepy VM named `Sleepy` in libvirt.
- Produces: `baseline.systemStateVersion :: string` and the exact generated hardware module used by `mkSleepyHost`.

- [ ] **Step 1: Read the guest facts without modifying its active generation**

In a terminal inside the VM, run:

```bash
nixos-option system.stateVersion
printf 'hostPlatform=' 
nix eval --impure --raw --expr 'builtins.currentSystem'
sudo nixos-generate-config --show-hardware > /tmp/sleepy-hardware-configuration.nix
nix-instantiate --parse /tmp/sleepy-hardware-configuration.nix >/dev/null
```

Expected: one quoted NixOS state-version value, `x86_64-linux`, and a successful parse with no output.

- [ ] **Step 2: Copy the generated module verbatim and record only stable facts**

Still inside the guest, generate the baseline file directly from the observed value:

```bash
state_version=$(nixos-option system.stateVersion 2>/dev/null | sed -nE 's/^[[:space:]]*"([0-9]+\.[0-9]+)"[[:space:]]*$/\1/p' | head -n1)
test -n "$state_version"
printf '{ system = "x86_64-linux"; systemStateVersion = "%s"; }\n' "$state_version" > /tmp/sleepy-baseline.nix
nix-instantiate --parse /tmp/sleepy-baseline.nix >/dev/null
```

Copy `/tmp/sleepy-hardware-configuration.nix` and `/tmp/sleepy-baseline.nix` to their repository paths. Verify:

```bash
nix-instantiate --parse hosts/sleepy-vm/hardware-configuration.nix >/dev/null
nix-instantiate --parse hosts/sleepy-vm/baseline.nix >/dev/null
```

Expected: all commands exit 0 and print no matches.

- [ ] **Step 3: Document the captured contract**

Create `docs/vm-baseline.md` containing the VM name, capture date, observed state version, architecture, disk bus from `virsh domblklist Sleepy --details`, and the rule that future upgrades never change `systemStateVersion` automatically. Do not include UUIDs, credentials, MAC addresses, or secrets.

- [ ] **Step 4: Commit**

```bash
git add hosts/sleepy-vm docs/vm-baseline.md
git commit -m "docs: capture Sleepy VM baseline"
git status --short
```

Expected: commit succeeds and status is empty.

---

### Task 2: Establish the Flake and Package Boundaries

**Files:**
- Create: `flake.nix`
- Create: `flake.lock`
- Create: `lib/for-all-systems.nix`
- Create: `packages/default.nix`
- Create: `packages/sleepy-branding/default.nix`
- Create: `packages/sleepy-branding/logo.svg`
- Create: `packages/sleepy-shell/default.nix`
- Create: `packages/sleepy-shell/src/shell.qml`
- Create: `overlays/default.nix`
- Create: `LICENSE`
- Create: `README.md`

**Interfaces:**
- Consumes: `baseline.system`, `nixpkgs`, and Home Manager inputs.
- Produces: `forAllSystems`, `packages.${system}.sleepy-branding`, `packages.${system}.sleepy-shell`, `overlays.default`, `formatter`, and `devShells.default`.

- [ ] **Step 1: Write the failing flake contract check**

Create `lib/for-all-systems.nix`:

```nix
{lib, systems}: function:
lib.genAttrs systems (system: function system)
```

Run before `flake.nix` exists:

```bash
nix flake show
```

Expected: FAIL because the directory has no flake.

- [ ] **Step 2: Add minimal real packages, not empty placeholders**

`packages/sleepy-branding/default.nix` installs `logo.svg` under `$out/share/sleepy/branding/`. The SVG must use a `32 32` view box and the Lunar Minimal colors `#b9a7ff` and `#181620`.

`packages/sleepy-shell/src/shell.qml`:

```qml
import Quickshell
import QtQuick

ShellRoot {
    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
        }
        implicitWidth: 52
        color: "#181620"
    }
}
```

`packages/sleepy-shell/default.nix`:

```nix
{stdenvNoCC}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-shell";
  version = "0.1.0";
  src = ./src;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/quickshell/sleepy"
    cp -R . "$out/share/quickshell/sleepy/"
    runHook postInstall
  '';
}
```

`packages/default.nix`:

```nix
{pkgs}: {
  sleepy-branding = pkgs.callPackage ./sleepy-branding {};
  sleepy-shell = pkgs.callPackage ./sleepy-shell {};
}
```

`overlays/default.nix`:

```nix
final: _prev:
import ../packages {pkgs = final;}
```

- [ ] **Step 3: Add the flake public package API**

Create `flake.nix` with inputs pinned to `nixos-unstable` and Home Manager following the same `nixpkgs`. Define `supportedSystems = [ "x86_64-linux" ]`, import `forAllSystems`, apply only `overlays.default`, and export:

```nix
packages = forAllSystems (system: let pkgs = mkPkgs system; in {
  inherit (pkgs) sleepy-branding sleepy-shell;
  default = pkgs.sleepy-shell;
});
formatter = forAllSystems (system: (mkPkgs system).alejandra);
devShells = forAllSystems (system: let pkgs = mkPkgs system; in {
  default = pkgs.mkShellNoCC {
    packages = with pkgs; [alejandra deadnix statix shellcheck qt6Packages.qtdeclarative];
  };
});
overlays.default = import ./overlays;
```

Keep `nixosConfigurations`, modules, Home Manager outputs, and checks absent until their producing tasks.

- [ ] **Step 4: Lock and build both packages**

```bash
nix flake lock
nix build .#sleepy-branding .#sleepy-shell
nix eval .#packages.x86_64-linux.sleepy-shell.pname --raw
```

Expected: both derivations build and the eval prints `sleepy-shell`.

- [ ] **Step 5: Add project metadata**

Copy the unmodified GPL-3.0 license text from an authoritative local license bundle or GNU source into `LICENSE`. Add a short `README.md` naming Sleepy Linux, identifying NixOS as its base, marking the project pre-alpha, and linking the design and plan.

- [ ] **Step 6: Format and commit**

```bash
nix fmt
git diff --check
git add flake.nix flake.lock lib packages overlays LICENSE README.md
git commit -m "feat: establish Sleepy flake foundation"
```

Expected: package builds still pass and status is empty.

---

### Task 3: Add Reusable Module Interfaces and Dual Home Manager Modes

**Files:**
- Create: `lib/mkSleepyHost.nix`
- Create: `hosts/sleepy-vm/default.nix`
- Create: `profiles/desktop.nix`
- Create: `modules/nixos/default.nix`
- Create: `modules/home/default.nix`
- Create: `modules/home/options.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: `mkSleepyHost {system, hostName, primaryUser, hardwareModule, extraModules ? []}`.
- Produces: `nixosModules.sleepy`, `homeManagerModules.sleepy`, `nixosConfigurations.sleepy-vm`, and `homeConfigurations."lazy@sleepy-vm"`.

- [ ] **Step 1: Add a failing output assertion**

Run:

```bash
nix eval .#nixosConfigurations.sleepy-vm.config.networking.hostName --raw
```

Expected: FAIL because the output does not exist.

- [ ] **Step 2: Define the Home Manager option boundary**

`modules/home/options.nix` defines:

```nix
options.sleepy = {
  enable = lib.mkEnableOption "the Sleepy Linux desktop";
  primaryUser = lib.mkOption {type = lib.types.str;};
  brandingPackage = lib.mkOption {type = lib.types.package;};
  shellPackage = lib.mkOption {type = lib.types.package;};
};
```

`modules/home/default.nix` imports `options.nix`, `apps`, `niri`, and `quickshell`. The last three modules are added as buildable minimal modules in their producing tasks; until then, import only files that exist.

- [ ] **Step 3: Implement the host factory**

`lib/mkSleepyHost.nix` must use `inputs.nixpkgs.lib.nixosSystem`, pass `inputs`, `primaryUser`, and `sleepyVersion = "0.1.0"` through `specialArgs`, and compose only:

```nix
[
  hardwareModule
  ../profiles/desktop.nix
  inputs.home-manager.nixosModules.home-manager
  {networking.hostName = hostName;}
] ++ extraModules
```

The factory must not inspect `local/` or ambient environment variables.

- [ ] **Step 4: Compose integrated and standalone Home Manager**

`profiles/desktop.nix` imports `modules/nixos/default.nix`, sets `home-manager.useGlobalPkgs = true`, `home-manager.useUserPackages = true`, and imports `modules/home/default.nix` for `home-manager.users.${primaryUser}`.

`hosts/sleepy-vm/default.nix` imports `baseline.nix` and calls the host factory with the captured hardware module.

Add the four public outputs to `flake.nix`. The standalone configuration must use the same `modules/home/default.nix`, set `sleepy.enable = true`, `home.username = "lazy"`, `home.homeDirectory = "/home/lazy"`, and `home.stateVersion = "26.05"`.

- [ ] **Step 5: Evaluate both modes**

```bash
nix eval .#nixosConfigurations.sleepy-vm.config.networking.hostName --raw
nix eval .#homeConfigurations."lazy@sleepy-vm".config.home.username --raw
nix eval .#nixosConfigurations.sleepy-vm.config.system.stateVersion --raw
```

Expected: `sleepy-vm`, `lazy`, and the exact captured state-version value.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add flake.nix lib/mkSleepyHost.nix hosts profiles modules
git commit -m "feat: add reusable Sleepy module outputs"
```

---

### Task 4: Implement Base System and Safe Branding

**Files:**
- Create: `modules/nixos/base/default.nix`
- Create: `modules/nixos/branding/default.nix`
- Modify: `modules/nixos/default.nix`

**Interfaces:**
- Consumes: `primaryUser` and `sleepyVersion` special arguments.
- Produces: a normal user, minimal desktop services, and safe Sleepy `os-release` metadata.

- [ ] **Step 1: Write failing evaluations**

```bash
nix eval .#nixosConfigurations.sleepy-vm.config.users.users.lazy.isNormalUser
nix eval .#nixosConfigurations.sleepy-vm.config.system.nixos.distroId --raw
```

Expected: the first value is absent or false and the second is not `sleepy`.

- [ ] **Step 2: Implement the base module**

Enable the primary user with `isNormalUser = true`, wheel membership, Fish, NetworkManager, PipeWire with ALSA and PulseAudio, rtkit, dconf, UPower, and polkit. Set `i18n.defaultLocale = "en_US.UTF-8"` and `services.xserver.xkb.layout = "us,ru"` with `options = "grp:alt_shift_toggle"`. Do not add unrelated desktop applications.

- [ ] **Step 3: Implement safe branding**

Set:

```nix
system.nixos = {
  distroId = "sleepy";
  distroName = "Sleepy Linux";
  vendorId = "sleepy";
  vendorName = "Sleepy Linux";
  extraOSReleaseArgs = {
    ID_LIKE = "nixos";
    VARIANT = "Sleepy Desktop";
    VARIANT_ID = "sleepy";
    SLEEPY_VERSION = sleepyVersion;
    LOGO = "sleepy";
  };
};
```

Do not rename Nix commands, NixOS module paths, `system.stateVersion`, store paths, or service identities.

- [ ] **Step 4: Evaluate contracts and build the system closure**

```bash
nix eval .#nixosConfigurations.sleepy-vm.config.system.nixos.distroId --raw
nix eval .#nixosConfigurations.sleepy-vm.config.system.nixos.extraOSReleaseArgs.ID_LIKE --raw
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel
```

Expected: `sleepy`, `nixos`, and a successful system build.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixos
git commit -m "feat: add Sleepy base system and branding"
```

---

### Task 5: Generate and Validate Modular Niri Configuration

**Files:**
- Create: `modules/home/niri/default.nix`
- Create: `modules/home/niri/config/config.kdl`
- Create: `modules/home/niri/config/input.kdl`
- Create: `modules/home/niri/config/appearance.kdl`
- Create: `modules/home/niri/config/bindings.kdl`
- Create: `modules/home/niri/config/rules.kdl`
- Create: `modules/home/niri/config/startup.kdl`
- Create: `checks/niri-config.nix`
- Modify: `modules/home/default.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: `pkgs.niri`, `pkgs.xwayland-satellite`, Ghostty, and Fuzzel executable names.
- Produces: read-only `~/.config/niri/*.kdl`, emergency keyboard controls, and `checks.${system}.niri-config`.

- [ ] **Step 1: Write an invalid include capability probe**

Create the check derivation to copy the full config tree, deliberately point `niri validate --config` at `config.kdl`, and initially omit `input.kdl`.

```bash
nix build .#checks.x86_64-linux.niri-config -L
```

Expected: FAIL with a missing include error. This proves the selected parser evaluates includes rather than accepting an unused file.

- [ ] **Step 2: Add the generated top-level KDL**

`config.kdl` contains only ordered includes:

```kdl
include "input.kdl"
include "appearance.kdl"
include "bindings.kdl"
include "rules.kdl"
include "startup.kdl"
```

`input.kdl` configures `layout "us,ru"` and `options "grp:alt_shift_toggle"`. `appearance.kdl` defines a dark background, `gaps 12`, an active focus ring with `active-color "#b9a7ff"`, and `prefer-no-csd`. `rules.kdl` contains a single `window-rule` with `geometry-corner-radius 10.0` and `clip-to-geometry true`; the pinned Niri validator is the capability gate.

- [ ] **Step 3: Add emergency bindings and useful startup**

`bindings.kdl` includes at minimum:

```kdl
binds {
    Mod+T { spawn "ghostty"; }
    Mod+Return { spawn "ghostty"; }
    Mod+D { spawn "fuzzel"; }
    Mod+Shift+E { quit; }
    Mod+Q { close-window; }
    Mod+Left { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up { focus-window-up; }
    Mod+Down { focus-window-down; }
}
```

`startup.kdl` starts `nm-applet --indicator`, which supplies the MVP network tray item without placing service logic in Quickshell.

- [ ] **Step 4: Install KDL as read-only Home Manager sources**

Map every file explicitly:

```nix
xdg.configFile = {
  "niri/config.kdl".source = ./config/config.kdl;
  "niri/input.kdl".source = ./config/input.kdl;
  "niri/appearance.kdl".source = ./config/appearance.kdl;
  "niri/bindings.kdl".source = ./config/bindings.kdl;
  "niri/rules.kdl".source = ./config/rules.kdl;
  "niri/startup.kdl".source = ./config/startup.kdl;
};
```

Do not use `text`, `force`, an activation script, or any write to a mutable KDL path.

- [ ] **Step 5: Make the validation check pass**

`checks/niri-config.nix` runs:

```bash
${pkgs.niri}/bin/niri validate --config "$config/config.kdl"
touch "$out"
```

Add it to `checks.${system}` and run:

```bash
nix build .#checks.x86_64-linux.niri-config -L
nix build .#homeConfigurations."lazy@sleepy-vm".activationPackage
```

Expected: both builds pass.

- [ ] **Step 6: Commit**

```bash
git add modules/home/niri checks/niri-config.nix flake.nix modules/home/default.nix
git commit -m "feat: add validated Niri configuration"
```

---

### Task 6: Add the Niri Login Session and Desktop Services

**Files:**
- Create: `modules/nixos/session/default.nix`
- Modify: `modules/nixos/default.nix`
- Create: `checks/session-contract.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: upstream `niri-session`, `niri.service`, and Niri-managed Xwayland Satellite integration.
- Produces: ReGreet login, Niri session, portals, policy authentication, and explicit graphical-session unit contracts.

- [ ] **Step 1: Write failing session evaluations**

```bash
nix eval .#nixosConfigurations.sleepy-vm.config.programs.niri.enable
nix eval .#nixosConfigurations.sleepy-vm.config.services.greetd.enable
```

Expected: both are false or absent.

- [ ] **Step 2: Enable upstream session integration**

Enable `programs.niri`, `services.greetd`, and `programs.regreet`. Use the ReGreet compositor configuration provided by the pinned NixOS module; do not create a custom Niri session wrapper. Put `xwayland-satellite`, `wl-clipboard`, `libnotify`, `networkmanagerapplet`, and one lightweight polkit agent in the system closure. Use Niri's built-in Xwayland Satellite integration and do not create a separate Satellite service.

- [ ] **Step 3: Configure portals without global backend overrides**

Keep the portal configuration supplied by `programs.niri` unless evaluation shows a missing file chooser. If an override is required, scope it to `xdg.portal.config.niri` and use GTK only for `org.freedesktop.impl.portal.FileChooser`. Never set `GDK_BACKEND` globally.

- [ ] **Step 4: Assert the lifecycle contract**

`checks/session-contract.nix` evaluates the NixOS configuration and fails unless:

- `programs.niri.enable` and `services.greetd.enable` are true;
- `pkgs.xwayland-satellite` is present in the Niri runtime closure;
- no Sleepy-defined `xwayland-satellite.service` exists;
- the upstream `niri.service` package is present.

Run:

```bash
nix build .#checks.x86_64-linux.session-contract
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/nixos/session checks/session-contract.nix flake.nix
git commit -m "feat: add Niri login session"
```

---

### Task 7: Add the Minimal User Application Layer

**Files:**
- Create: `modules/home/apps/default.nix`
- Modify: `modules/home/default.nix`

**Interfaces:**
- Consumes: the `sleepy.enable` option and standard `nixpkgs` packages.
- Produces: Firefox, Ghostty, Fish, Fuzzel, and immutable default application configuration.

- [ ] **Step 1: Write failing Home Manager package checks**

```bash
nix eval .#homeConfigurations."lazy@sleepy-vm".config.programs.firefox.enable
nix eval .#homeConfigurations."lazy@sleepy-vm".config.programs.ghostty.enable
```

Expected: false or absent.

- [ ] **Step 2: Configure only the default applications**

Enable `programs.firefox`, `programs.ghostty`, `programs.fish`, and `programs.fuzzel`. Set Ghostty's command to the Fish executable and use a dark background matching Lunar Minimal. Keep Fish's standard prompt. Configure Fuzzel with Ghostty as terminal and a compact dark theme. Add `jq`, `wl-clipboard`, and `libnotify` only where the Niri/Quickshell services consume them.

- [ ] **Step 3: Build integrated and standalone outputs**

```bash
nix build .#homeConfigurations."lazy@sleepy-vm".activationPackage
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel
```

Expected: both pass and neither activation output contains a user-installed application profile.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/home/apps modules/home/default.nix
git commit -m "feat: add default Sleepy applications"
```

---

### Task 8: Build the Modular Lunar Minimal Quickshell Panel

**Files:**
- Create: `packages/sleepy-shell/src/Theme.qml`
- Create: `packages/sleepy-shell/src/modules/panel/Panel.qml`
- Create: `packages/sleepy-shell/src/services/ClockService.qml`
- Create: `packages/sleepy-shell/src/services/NiriService.qml`
- Create: `packages/sleepy-shell/src/widgets/BrandMark.qml`
- Create: `packages/sleepy-shell/src/widgets/WorkspaceButton.qml`
- Create: `packages/sleepy-shell/src/widgets/Tray.qml`
- Create: `packages/sleepy-shell/src/widgets/Clock.qml`
- Create: `packages/sleepy-shell/src/defaults.json`
- Create: `packages/sleepy-shell/src/settings.schema.json`
- Modify: `packages/sleepy-shell/src/shell.qml`
- Modify: `packages/sleepy-shell/default.nix`

**Interfaces:**
- Consumes: `niri msg --json workspaces`, `SystemTray.items`, and the branding package path.
- Produces: one `PanelWindow` per screen, service-owned state, and no mutable file writes.

- [ ] **Step 1: Add failing source-boundary tests**

Create `checks/quickshell-contract.sh` to fail unless all are true:

```bash
test -f packages/sleepy-shell/src/services/NiriService.qml
test -f packages/sleepy-shell/src/modules/panel/Panel.qml
! rg -n 'settings\.json.*(write|remove)|force[[:space:]]*=' packages modules
! rg -n 'Process[[:space:]]*\{' packages/sleepy-shell/src/widgets
```

Run it now. Expected: FAIL because the modular files do not exist.

- [ ] **Step 2: Define stable theme and defaults interfaces**

`Theme.qml` is a `QtObject` with readonly values for `panelWidth: 52`, `background: "#181620"`, `surface: "#211f2a"`, `accent: "#b9a7ff"`, `text: "#f5f3ff"`, `muted: "#a9a4b8"`, `radius: 8`, and `spacing: 6`.

`defaults.json`:

```json
{
  "schemaVersion": 1,
  "panel": {
    "edge": "left",
    "width": 52,
    "alwaysVisible": true
  },
  "theme": {
    "name": "lunar-minimal"
  }
}
```

`settings.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion"],
  "properties": {
    "schemaVersion": {"const": 1},
    "panel": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "edge": {"const": "left"},
        "width": {"const": 52},
        "alwaysVisible": {"const": true}
      }
    },
    "theme": {
      "type": "object",
      "additionalProperties": false,
      "properties": {"name": {"const": "lunar-minimal"}}
    }
  }
}
```

No component reads or creates `~/.config/sleepy/settings.json` in this milestone.

- [ ] **Step 3: Implement service objects**

`ClockService.qml` owns one repeating `Timer` and exposes a formatted `time` property.

`NiriService.qml` owns a `Process` that runs:

```qml
command: ["niri", "msg", "--json", "workspaces"]
```

Use `StdioCollector` to parse the completed JSON, expose a sorted `workspaces` array, and rerun at a one-second MVP interval. Parse errors retain the last valid state and log one concise warning. Expose `focusWorkspace(index)` using `Quickshell.execDetached`; widgets never invoke commands directly.

- [ ] **Step 4: Implement focused widgets**

- `BrandMark.qml` displays the packaged SVG through a required `source` property.
- `WorkspaceButton.qml` accepts `index`, `active`, and `activate` properties.
- `Tray.qml` repeats `SystemTray.items` and displays each item's `icon`; missing icons render a small muted dot.
- `Clock.qml` renders the service string vertically or as two compact lines.

Each widget sets implicit dimensions and contains no system process, file, or settings logic.

- [ ] **Step 5: Compose the panel**

`Panel.qml` is a `Scope` using `Variants { model: Quickshell.screens }`. Each variant creates a `PanelWindow` anchored top, bottom, and left with `implicitWidth: theme.panelWidth`. Compose the brand mark and workspace column at top, a tray centered vertically, and clock/user indicator at bottom.

`shell.qml` creates one `Theme`, one `ClockService`, one `NiriService`, and one `Panel`, passing dependencies explicitly.

- [ ] **Step 6: Build and run static checks**

```bash
bash checks/quickshell-contract.sh
nix build .#sleepy-shell
nix develop -c qmllint packages/sleepy-shell/src/shell.qml
```

Expected: contract, package build, and `qmllint` all pass. Configure the development shell's QML import path from the pinned Quickshell/Qt packages; do not suppress unresolved imports or ordinary QML errors.

- [ ] **Step 7: Commit**

```bash
git add packages/sleepy-shell checks/quickshell-contract.sh
git commit -m "feat: add Lunar Minimal Quickshell panel"
```

---

### Task 9: Install and Harden the Quickshell Service

**Files:**
- Create: `modules/home/quickshell/default.nix`
- Modify: `modules/home/default.nix`
- Create: `checks/update-safety.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: Home Manager `programs.quickshell`, `sleepy-shell`, and `graphical-session.target`.
- Produces: `quickshell.service` with bounded restart behavior and a proof that mutable settings are unmanaged.

- [ ] **Step 1: Write failing service and ownership evaluations**

```bash
nix eval .#homeConfigurations."lazy@sleepy-vm".config.programs.quickshell.enable
nix eval .#homeConfigurations."lazy@sleepy-vm".config.systemd.user.services.quickshell.Unit.StartLimitBurst
```

Expected: false/absent and missing restart limit.

- [ ] **Step 2: Configure the Home Manager Quickshell module**

Set:

```nix
programs.quickshell = {
  enable = true;
  package = pkgs.quickshell;
  configs.sleepy = "${config.sleepy.shellPackage}/share/quickshell/sleepy";
  activeConfig = "sleepy";
  systemd = {
    enable = true;
    target = "graphical-session.target";
  };
};
```

Merge the generated service with:

```nix
systemd.user.services.quickshell = {
  Unit = {
    PartOf = ["graphical-session.target"];
    Requisite = ["graphical-session.target"];
    StartLimitIntervalSec = 30;
    StartLimitBurst = 3;
  };
  Service.RestartSec = 2;
};
```

Do not add settings-file activation code or `force = true`.

- [ ] **Step 3: Prove mutable settings are absent from the activation package**

`checks/update-safety.nix` receives the standalone activation package and fails if its `home-files` tree contains `sleepy/settings.json`, if any managed Niri file is writable, or if source modules contain `force = true`.

```bash
nix build .#checks.x86_64-linux.update-safety -L
nix eval .#homeConfigurations."lazy@sleepy-vm".config.systemd.user.services.quickshell.Unit.StartLimitBurst
```

Expected: build passes and eval prints `3`.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add modules/home/quickshell modules/home/default.nix checks/update-safety.nix flake.nix
git commit -m "feat: harden Quickshell session service"
```

---

### Task 10: Unify Checks and CI

**Files:**
- Create: `checks/default.nix`
- Create: `checks/source-clean.sh`
- Create: `.github/workflows/check.yml`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: all earlier derivations and contract checks.
- Produces: one `nix flake check` entry point with fast and build CI stages.

- [ ] **Step 1: Add the check aggregator**

`checks/default.nix` exports derivations named `nixos`, `home`, `niri-config`, `session-contract`, `update-safety`, `source-contracts`, and `quickshell`. `flake.nix` sets `checks = forAllSystems (...)` and passes the already-created host/home configurations rather than re-evaluating alternate copies.

- [ ] **Step 2: Verify the fast stage**

```bash
nix flake check --no-build --show-trace
```

Expected: evaluation succeeds without realizing the VM closure.

- [ ] **Step 3: Verify the complete stage**

```bash
nix flake check -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel -L
nix build .#homeConfigurations."lazy@sleepy-vm".activationPackage -L
```

Expected: all builds pass.

- [ ] **Step 4: Add CI with a clean-repository assertion**

`.github/workflows/check.yml` has:

1. a `fast` job running formatting, statix, deadnix, ShellCheck when scripts exist, and `nix flake check --no-build`;
2. a `build` job depending on `fast`, running full flake check plus NixOS/Home Manager builds;
3. a final `git status --porcelain=v1 --untracked-files=all` assertion that fails on unexpected files.

The checkout must use only committed files. The workflow must not create or restore `local/` or `secrets/` and must not package them as artifacts.

- [ ] **Step 5: Run the local CI equivalent and commit**

```bash
nix fmt -- --check .
statix check .
deadnix --fail .
shellcheck checks/*.sh
nix flake check -L
git add checks flake.nix .github/workflows/check.yml
git commit -m "ci: validate Sleepy desktop foundation"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
```

Expected: validation passes, the commit succeeds, and the final clean assertion prints no output.

---

### Task 11: Prove Fresh-Clone Reproducibility

**Files:**
- Create: `checks/fresh-clone.sh`
- Modify: `.github/workflows/check.yml`
- Modify: `checks/default.nix`

**Interfaces:**
- Consumes: committed Git tree and lock file only.
- Produces: a release-blocking proof that `local/` is not an implicit dependency.

- [ ] **Step 1: Write the isolated-clone check**

The script creates a temporary directory, clones the repository from its local path with `git clone --no-local`, asserts `local/` and `secrets/` are absent, and builds from the lock file:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
clone_root=$(mktemp -d)
trap 'rm -rf -- "$clone_root"' EXIT

git clone --quiet --no-local "$repo_root" "$clone_root/repo"
cd "$clone_root/repo"
test ! -e local
test ! -e secrets
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel --no-write-lock-file
test -z "$(git status --porcelain=v1 --untracked-files=all)"
```

It removes the temporary clone through a trap and never modifies the source repository.

- [ ] **Step 2: Make it release-blocking**

Run the script locally and from the CI build job. Expected: the clean clone builds the same locked derivation and contains no ignored local state.

- [ ] **Step 3: Commit**

```bash
shellcheck checks/fresh-clone.sh
bash checks/fresh-clone.sh
git add checks/fresh-clone.sh checks/default.nix .github/workflows/check.yml
git commit -m "test: prove fresh-clone reproducibility"
```

---

### Task 12: Deploy to Sleepy and Run the VM Acceptance Test

**Files:**
- Create: `docs/deployment.md`
- Create: `docs/recovery.md`
- Create: `docs/acceptance/desktop-foundation.md`

**Interfaces:**
- Consumes: the passing `nixosConfigurations.sleepy-vm` closure and existing libvirt VM.
- Produces: one activated, tested Sleepy generation and a repeatable acceptance record.

- [ ] **Step 1: Build before touching the active VM**

```bash
nix flake check -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel -L
```

Expected: both pass. Do not deploy a closure that fails either command.

- [ ] **Step 2: Capture user-owned state before activation**

Inside the VM, create a temporary evidence directory and record checksums without copying secrets into the repository:

```bash
evidence_dir=$(mktemp -d)
settings_file="$HOME/.config/sleepy/settings.json"
sentinel_file="$HOME/.local/share/sleepy-acceptance-sentinel"
mkdir -p "$(dirname "$settings_file")" "$(dirname "$sentinel_file")"
if test -e "$settings_file"; then
  printf 'existing\n' > "$evidence_dir/settings-origin"
else
  printf 'created\n' > "$evidence_dir/settings-origin"
  printf '{"schemaVersion":1}\n' > "$settings_file"
fi
printf 'Sleepy must preserve this file.\n' > "$sentinel_file"
sha256sum "$settings_file" "$sentinel_file" > "$evidence_dir/files.before"
nix profile list --json > "$evidence_dir/profile.before.json"
printf '%s\n' "$evidence_dir"
```

Keep the printed path for Step 5. Expected: all evidence files exist and contain no credential values.

- [ ] **Step 3: Make the repository available inside the guest and dry-activate**

Use the Git origin if it has been provided by this point; otherwise copy the clean tracked tree to `/etc/sleepy` through a temporary archive created by `git archive HEAD`. Inside the VM run:

```bash
cd /etc/sleepy
sudo nixos-rebuild dry-activate --flake .#sleepy-vm
sudo nixos-rebuild test --flake .#sleepy-vm
```

Expected: dry activation reports no unmanaged home-file overwrite and test activation succeeds without changing the boot default.

- [ ] **Step 4: Validate the session before permanent switch**

Log out, select the Sleepy Niri session in ReGreet, and verify:

```bash
systemctl --user is-active graphical-session.target
systemctl --user is-active quickshell.service
systemctl --user show-environment | rg '^(WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|NIRI_SOCKET)='
niri msg --json workspaces | jq -e 'length > 0'
```

Expected: both units active, all required variables present, and at least one workspace.

- [ ] **Step 5: Run interactive acceptance and compare user-owned state**

Record pass/fail evidence in `docs/acceptance/desktop-foundation.md` for:

- ReGreet login into Niri;
- 52 px Lunar Minimal left panel;
- workspace indicator changes;
- tray network indicator and clock;
- `Mod+T` and `Mod+Return` opening Ghostty after virt-manager keyboard capture;
- `Mod+D` opening Fuzzel;
- Firefox and its file portal;
- one X11 application through Niri-managed Xwayland Satellite;
- US/RU switching with `Alt+Shift`;
- three forced Quickshell failures reaching the start limit while terminal, launcher, navigation, and logout bindings still work;
- logout stopping `graphical-session.target` and its bound services.
- a deliberately invalid candidate configuration failing before activation while the current and previous generations remain usable.

Using the `evidence_dir` from Step 2, verify the rebuild did not change user-owned state:

```bash
sha256sum -c "$evidence_dir/files.before"
nix profile list --json > "$evidence_dir/profile.after.json"
diff -u "$evidence_dir/profile.before.json" "$evidence_dir/profile.after.json"
if grep -qx created "$evidence_dir/settings-origin"; then
  rm "$settings_file"
fi
```

Expected: checksums pass, the profile diff is empty, and only a settings file created by this test is removed. A file that existed before the test is never removed.

- [ ] **Step 6: Switch permanently only after acceptance passes**

```bash
sudo nixos-rebuild switch --flake /etc/sleepy#sleepy-vm
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Expected: the new generation is active and at least one previous generation remains available.

- [ ] **Step 7: Document recovery**

`docs/recovery.md` covers selecting a previous boot generation, switching to a TTY, inspecting `journalctl --user -u quickshell.service -u niri.service`, restarting Quickshell, and reverting with `nixos-rebuild switch --rollback`. It must distinguish host-side Super-key interception from a guest Niri binding failure.

- [ ] **Step 8: Commit acceptance evidence**

```bash
git add docs/deployment.md docs/recovery.md docs/acceptance/desktop-foundation.md
git commit -m "docs: record Sleepy desktop acceptance"
git status --short
```

Expected: status is empty and all acceptance items are explicitly marked passed.

---

## Final Verification

Run from a clean checkout with no `local/` or `secrets/` directory:

```bash
nix fmt -- --check .
statix check .
deadnix --fail .
shellcheck checks/*.sh
nix flake check --no-build --show-trace
nix flake check -L
bash checks/fresh-clone.sh
git diff --check
test -z "$(git status --porcelain=v1 --untracked-files=all)"
```

Expected: every command exits 0, the repository remains clean, and the VM acceptance record contains no failed item.
