# Caelestia v2.4.0 Full-Parity Sleepy Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reduced Sleepy `Core*` production shell with the complete modular Caelestia Shell v2.4.0 interface under Sleepy identity, preserve the secure Sleepy session boundary, and prove visual/behavioral parity in automated and real virt-manager acceptance.

**Architecture:** Keep the imported upstream visual graph and native helpers recognizable, enable direct fixed-argv system integrations where upstream behavior depends on them, and isolate Sleepy naming, packaging, compatibility, and security changes. Existing `sleepy-sessiond` protocol-v3 services remain available for exact-fit adapters and protected session operations, but ordinary desktop features may use Quickshell providers, Hyprland IPC, or audited command-line utilities directly.

**Tech Stack:** Qt 6, Quickshell/QML, C++20, CMake/Ninja, Hyprland, `hyprctl`, NetworkManager/`nmcli`, PipeWire, UPower, MPRIS, SystemTray/DBusMenu, PAM, Rust 2021, Tokio, systemd/UWSM, Nix flakes, Home Manager, ReGreet, libvirt/QEMU/SPICE.

**Spec:** `docs/superpowers/specs/2026-09-01-caelestia-v2.4.0-parity-design.md`

## Global Constraints

- Work on `feat/hyprland-sleepy-desktop` in root `sleepy`, `sleepy-desktop`, `sleepy-session`, and `sleepy-sdk`.
- Fork only `caelestia-dots/shell` v2.4.0 commit `24aa15eefdb146350d2548c0a015b04eddbd1008`; do not copy from the unlicensed `caelestia-dots/caelestia` repository.
- Preserve GPL-3.0-only notices, `NOTICE`, `UPSTREAM.json`, corresponding source, and build scripts.
- Runtime processes, units, paths, QML namespaces, commands, IPC, settings, and visible product labels are Sleepy.
- Preserve upstream geometry, typography, colors, effects, animation timing/easing, states, gestures, keyboard behavior, and feature coverage except Sleepy name/logo substitutions.
- `hyprctl`, `nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`, `powerprofilesctl`, `wl-copy`, `swappy`, and desktop application execution are permitted only as fixed argv without shell interpretation.
- Passwords, PAM material, and NetworkManager secrets never enter argv, logs, generic QML properties, snapshots, or evidence.
- `sleepy-locker` remains the sole unlock authority; suspend requires confirmed lock.
- One provider owns each state/action pair; a feature must not combine direct and daemon-backed mutation authorities.
- `approved-deviation` and `deferred-environment` are not completion statuses for reachable parity entries.
- Preserve prior-generation rollback and legacy Sleepy state.
- Run unqualified commands from the repository named by the task; commands
  containing `git -C` or `--manifest-path` carry their own explicit location.

---

### Task 1: Replace deviation-friendly parity gates with full-parity contracts

**Repository:** `sleepy-desktop`

**Files:**
- Create: `tests/full-parity-contract.sh`
- Create: `tests/patch-inventory.json`
- Create: `tests/patch-inventory.sh`
- Modify: `tests/lib/parity-validator.sh`
- Modify: `tests/parity-validator-test.sh`
- Modify: `tests/parity-manifest.json`
- Modify: `tests/parity.sh`
- Modify: `UPSTREAM.json`

**Interfaces:**
- Consumes: the existing 403-entry v2.4.0 manifest and immutable upstream inventory.
- Produces: a validator accepting only `verified` for reachable behavior and `excluded-non-runtime` for unreachable/build/license paths, plus a reviewed inventory of every Sleepy patch to imported source.

- [ ] **Step 1: Write the failing completion-policy test**

Create `tests/full-parity-contract.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="$root/tests/parity-manifest.json"
jq -e '[.entries[] | select(.behaviorStatus != "verified" and .behaviorStatus != "excluded-non-runtime")] | length == 0' "$manifest" >/dev/null
jq -e '[.objectiveCases[] | select(.status != "verified")] | length == 0' "$manifest" >/dev/null
jq -e '.referenceComparison.status == "verified"' "$manifest" >/dev/null
! rg -n 'approved-deviation|deferred-environment|drop-with-reason' "$manifest"
```

- [ ] **Step 2: Run the new contract and confirm the known failure**

Run: `bash tests/full-parity-contract.sh`

Expected: FAIL because the current manifest contains 112 approved deviations and deferred reference/VM outcomes.

- [ ] **Step 3: Tighten validator types before changing evidence**

Change `tests/lib/parity-validator.sh` so reachable entries accept only
`verified`; accept `excluded-non-runtime` only when `disposition` is one of
`build-only`, `license`, `unreachable`, or `replaced-asset`, with nonempty
`exclusionReason` and, for `replaced-asset`, `replacementPath`.

- [ ] **Step 4: Add negative validator fixtures**

Extend `tests/parity-validator-test.sh` to prove that
`approved-deviation`, `deferred-environment`, an excluded reachable QML file,
and a replacement asset without `replacementPath` each fail validation.

- [ ] **Step 5: Add the Sleepy patch inventory**

Create `tests/patch-inventory.json` with schema fields
`path`, `upstreamPath`, `category`, `reason`, and `tests`; allow categories
`identity`, `packaging`, `compatibility`, `security`, and `branding`. Seed it
with `src/shell.qml`, `src/modules/lock/**`, `src/services/**`, and
`src/plugin/src/Sleepy/**`, then make `tests/patch-inventory.sh` reject unknown
keys, missing files, duplicate paths, and active modified imported files not
covered by the inventory.

- [ ] **Step 6: Run the new gates without registering the completion gate yet**

Keep `tests/full-parity-contract.sh` out of `tests/run.sh` until Task 11 closes
the manifest. Run the validator unit test and patch inventory independently:

```bash
bash tests/parity-validator-test.sh
bash tests/patch-inventory.sh
```

Expected: PASS.

- [ ] **Step 7: Commit the stricter contract**

```bash
git add UPSTREAM.json tests
git commit -m "test: require complete Caelestia parity"
```

### Task 2: Activate the complete modular shell entry graph

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/shell.qml`
- Create: `tests/qml/tst_upstream_shell_graph.qml`
- Modify: `tests/active-graph.py`
- Modify: `tests/active-graph.sh`
- Modify: `tests/closed-imports.sh`
- Modify: `tests/service-boundary.sh`
- Modify: `tests/ipc-contracts.sh`
- Modify: `src/CMakeLists.txt`

**Interfaces:**
- Consumes: imported `GSFLoader`, `ServiceLoader`, `Background`, `Drawers`, `AreaPicker`, `Shortcuts`, `BatteryMonitor`, and `IdleMonitors` types.
- Produces: a production `ShellRoot` that instantiates the upstream module graph and no longer instantiates `Core.CoreDesktopWindows`.

- [ ] **Step 1: Write the failing production-graph QML test**

Create `tests/qml/tst_upstream_shell_graph.qml` that loads `src/shell.qml` and
asserts named object markers for `background`, `drawers`, `areaPicker`,
`shortcuts`, `batteryMonitor`, and `idleMonitors`, while asserting no active
object has `objectName === "sleepyCoreDesktop"`.

- [ ] **Step 2: Run the focused test and confirm failure**

Run:

```bash
qmltestrunner -input tests/qml/tst_upstream_shell_graph.qml -import src -v1
```

Expected: FAIL because production currently creates `CoreDesktopWindows`.

- [ ] **Step 3: Restore the modular root**

Change `src/shell.qml` to import `modules`, `modules/drawers`,
`modules/background`, and `modules/areapicker`; instantiate `GSFLoader`,
`ServiceLoader`, `Background`, `Drawers`, `AreaPicker`, `Shortcuts`,
`BatteryMonitor`, and `IdleMonitors`. Keep `ShellId sleepy`, Sleepy crash URL,
Sleepy theme tokens, and `ShellState.shellRoot`. Do not instantiate the
decorative upstream `Lock`; route lock requests to `sleepy-locker`.

- [ ] **Step 4: Convert quarantine gates into active-graph safety gates**

Remove assertions that forbid `modules/` and Quickshell services. Make
`tests/active-graph.py` reject only Caelestia runtime identities, shell
interpreters, credential-bearing argv, unreviewed native modules, and imports
outside the installed Sleepy tree.

- [ ] **Step 5: Package the full non-secret visual graph**

Keep installing `assets`, `components`, `modules`, `services`, and `utils`.
Continue excluding upstream PAM snippets and the decorative lock process entry;
package the lock visuals through Task 9's dedicated locker target.

- [ ] **Step 6: Run shell graph tests**

```bash
bash tests/active-graph.sh
bash tests/closed-imports.sh
bash tests/ipc-contracts.sh
qmltestrunner -input tests/qml/tst_upstream_shell_graph.qml -import src -v1
```

Expected: PASS.

- [ ] **Step 7: Commit the active modular graph**

```bash
git add src/shell.qml src/CMakeLists.txt tests
git commit -m "feat: activate the complete modular shell graph"
```

### Task 3: Build the complete audited native QML plugin

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/plugin/src/Sleepy/CMakeLists.txt`
- Modify: `src/plugin/CMakeLists.txt`
- Modify: `src/CMakeLists.txt`
- Modify: `flake.nix`
- Modify: `tests/native-plugin-contracts.sh`
- Create: `tests/qml/tst_native_full_plugin.qml`

**Interfaces:**
- Consumes: imported Sleepy-renamed plugin sources.
- Produces: QML types required by the full graph, including Settings, Config, Components, Blobs, Images, Models, Services, calculator, requests, and toaster helpers.

- [ ] **Step 1: Write a failing QML type-instantiation test**

Create `tests/qml/tst_native_full_plugin.qml` importing `Sleepy`,
`Sleepy.Models`, and `Sleepy.Services`, then instantiate `AppDb`,
`FileSystemModel`, `Qalculator`, and one resource service type. Assert each
component reaches `Component.Ready`.

- [ ] **Step 2: Run the packaged plugin smoke and confirm missing types**

Run: `bash tests/native-plugin-contracts.sh`

Expected: FAIL because only render-helper submodules are currently built.

- [ ] **Step 3: Enable the imported plugin submodules**

Add the existing `Models` and `Services` subdirectories and the existing
calculator/request sources to the Sleepy CMake target. Preserve the renamed
`Sleepy` URI and compile definitions; do not restore a Caelestia namespace.

- [ ] **Step 4: Add exact native dependencies to Nix**

Add `aubio`, `pipewire`, `libcava`, `lm_sensors`, `libqalculate`, and required
Qt image/shader libraries to `nativePlugin.buildInputs`; add `pkg-config`,
`cmake`, `ninja`, and Qt shader tooling to native build inputs.

- [ ] **Step 5: Verify plugin metadata and loadability**

```bash
bash tests/native-plugin-contracts.sh
nix build .#sleepy-qml-plugin -L
```

Expected: the generated `qmldir` exports every type used by the active graph
and contains no `Caelestia` URI.

- [ ] **Step 6: Commit the plugin graph**

```bash
git add src/plugin src/CMakeLists.txt flake.nix tests
git commit -m "feat: build the complete Sleepy QML plugin"
```

### Task 4: Restore complete settings and Sleepy runtime identity

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/plugin/src/Sleepy/Config/**`
- Modify: `src/plugin/src/Sleepy/Settings/**`
- Modify: `src/utils/Paths.qml`
- Modify: `src/services/ShellState.qml`
- Modify: `src/modules/nexus/pages/AboutPage.qml`
- Modify: `UPSTREAM.json`
- Modify: `tests/runtime-names.sh`
- Create: `tests/qml/tst_full_settings.qml`

**Interfaces:**
- Consumes: the upstream v2.4.0 settings schema and defaults.
- Produces: complete settings under Sleepy XDG paths with unknown-key preservation, per-monitor overrides, quarantine, and exact upstream defaults except branding/apps.

- [ ] **Step 1: Write failing settings coverage tests**

In `tst_full_settings.qml`, load a fixture covering appearance, fonts,
animations, transparency, background, bar, dashboard, launcher, lock, nexus,
notifications, OSD, services, sidebar, utilities, and per-monitor overrides.
Assert a read/write/read cycle preserves an unknown compatible key.

- [ ] **Step 2: Extend runtime identity tests**

Make `tests/runtime-names.sh` reject active `caelestia` executables, QML URIs,
units, sockets, paths, configuration keys, IPC commands, and visible strings;
allow only `NOTICE`, `UPSTREAM.json`, SPDX/provenance comments, and parity
fixtures.

- [ ] **Step 3: Implement XDG Sleepy paths**

Map global settings to `$XDG_CONFIG_HOME/sleepy/shell.json`, per-monitor
settings to `$XDG_CONFIG_HOME/sleepy/monitors/<monitor>/shell.json`, state to
`$XDG_STATE_HOME/sleepy`, cache to `$XDG_CACHE_HOME/sleepy`, and data to
`$XDG_DATA_HOME/sleepy`.

- [ ] **Step 4: Restore every upstream setting node and default**

Enable the complete imported Config/Settings node graph. Change only product
logo/name, default Ghostty/Firefox applications, and Sleepy-owned paths.

- [ ] **Step 5: Verify identity and settings**

```bash
bash tests/runtime-names.sh
qmltestrunner -input tests/qml/tst_full_settings.qml -import src -v1
```

Expected: PASS with no active Caelestia identity.

- [ ] **Step 6: Commit settings and identity**

```bash
git add src UPSTREAM.json tests
git commit -m "feat: restore full settings under Sleepy identity"
```

### Task 5: Establish the direct-integration safety boundary

**Repository:** `sleepy-desktop`

**Files:**
- Create: `tests/direct-integrations.json`
- Create: `tests/direct-integrations.sh`
- Modify: `tests/service-boundary.sh`
- Modify: `tests/command-builders.sh`
- Modify: `src/services/Hypr.qml`
- Modify: `src/services/Nmcli.qml`
- Modify: `src/services/Audio.qml`
- Modify: `src/services/Brightness.qml`
- Modify: `src/services/Players.qml`
- Modify: `src/services/Notifs.qml`

**Interfaces:**
- Consumes: Quickshell service APIs and fixed system utilities.
- Produces: one documented provider per feature with safe argv, bounded processes, observed-state reconciliation, and no secret-bearing command lines.

- [ ] **Step 1: Create the direct integration registry**

Record provider IDs `hyprland`, `network`, `audio`, `brightness`, `media`,
`notifications`, `tray`, `power`, `clipboard`, `screenshot`, and `applications`.
Each entry contains `owner`, `mechanism`, `commands`, `stateSource`,
`mutationSource`, `secretPolicy`, and `tests`.

- [ ] **Step 2: Write failing source-safety tests**

Make `tests/direct-integrations.sh` reject `sh -c`, `bash -c`, `fish -c`,
`eval`, command strings where an argv array is required, password/PSK
arguments, unregistered executables, and a feature whose state/mutation owners
differ without an explicit reconciliation adapter.

- [ ] **Step 3: Permit reviewed providers in the former daemon-only gate**

Rewrite `tests/service-boundary.sh` to allow Quickshell Hyprland, PipeWire,
UPower, MPRIS, Notifications, and SystemTray imports and registered fixed-argv
commands. Continue rejecting Caelestia runtime APIs and arbitrary execution.

- [ ] **Step 4: Normalize provider completion and refresh behavior**

For each listed service, expose `available`, `busy`, `lastError`, and a refresh
path. On mutation completion, refresh observed state; on failure, retain the
last observed state and emit the upstream-equivalent toast.

- [ ] **Step 5: Run the safety suite**

```bash
bash tests/direct-integrations.sh
bash tests/service-boundary.sh
bash tests/command-builders.sh
```

Expected: PASS.

- [ ] **Step 6: Commit the direct provider boundary**

```bash
git add src/services tests
git commit -m "feat: allow audited direct desktop integrations"
```

### Task 6: Restore bar, background, workspaces, tray, and OSD parity

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/modules/bar/**`
- Modify: `src/modules/background/**`
- Modify: `src/modules/osd/**`
- Modify: `src/components/**`
- Modify: `src/services/Hypr.qml`
- Modify: `src/services/Screens.qml`
- Create: `tests/qml/tst_full_bar_background_osd.qml`
- Modify: `tests/parity-manifest.json`

**Interfaces:**
- Consumes: Hyprland monitors/workspaces/clients, SystemTray/DBusMenu, PipeWire/UPower/brightness state, wallpaper/colors, and animation tokens.
- Produces: original per-output bar/taskbar, workspace shapes/windows, popouts, background/clock/visualizer, tray menus, and OSD.

- [ ] **Step 1: Write deterministic two-output behavior tests**

Cover active/occupied/special workspaces, active-window title, tray nested menu
activation, bar hover reveal, volume/brightness scroll, fullscreen suppression,
mixed scale, monitor hotplug, and volume/mic/brightness/power OSD transitions.

- [ ] **Step 2: Run the focused test and record failures**

Run: `qmltestrunner -input tests/qml/tst_full_bar_background_osd.qml -import src -v1`

Expected: FAIL until the original modules are fully connected.

- [ ] **Step 3: Connect original modules to direct providers**

Preserve upstream anchors, tokens, shapes, timings, and component composition.
Replace only provider names and Sleepy branding references.

- [ ] **Step 4: Convert covered manifest entries to verified**

Update the exact bar/background/tray/OSD entries with the new QML test case
identities; do not change unrelated entries.

- [ ] **Step 5: Run software and RHI tests**

```bash
qmltestrunner -input tests/qml/tst_full_bar_background_osd.qml -import src -v1
QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 qmltestrunner -input tests/qml/tst_full_bar_background_osd.qml -import src -v1
```

Expected: PASS.

- [ ] **Step 6: Commit the first complete visual slice**

```bash
git add src tests
git commit -m "feat: restore Caelestia bar background and OSD parity"
```

### Task 7: Restore launcher, drawers, and window interaction parity

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/modules/drawers/**`
- Modify: `src/modules/launcher/**`
- Modify: `src/modules/windowinfo/**`
- Modify: `src/modules/areapicker/**`
- Modify: `src/services/ShellState.qml`
- Modify: `src/services/Wallpapers.qml`
- Create: `tests/qml/tst_full_launcher_drawers_windowinfo.qml`
- Modify: `tests/parity-manifest.json`

**Interfaces:**
- Consumes: desktop application index, calculator, schemes, wallpapers, Hyprland window state/actions, image helpers, clipboard, and area-picker tools.
- Produces: launcher modes, drawer gestures, window details/preview/actions, wallpaper picker, calculation copy, screenshot selection, and color picking.

- [ ] **Step 1: Write keyboard, pointer, and failure-state tests**

Cover launcher open/close, app search/launch, calculation, scheme selection,
wallpaper selection, favourite/hidden apps, Vim keys, Home/End, Escape/focus
return, drawer drag thresholds, window focus/move/close/fullscreen/group/pin,
and unavailable providers.

- [ ] **Step 2: Restore upstream launcher and drawer composition**

Use the imported Searcher, AppDb, FileSystemModel, Qalculator, wallpaper model,
Hyprland types, and original animations. Replace `caelestia` actions with
Sleepy commands or direct provider calls producing the same result.

- [ ] **Step 3: Keep execution argv-safe**

Application launch uses desktop-entry argv; calculator copy uses
`["wl-copy", result]`; area picker uses fixed `hyprctl cursorpos -j` and
`swappy -f <approved-path>` arrays. Remove the interactive `fish -C` calculator
fallback or replace it with a fixed `qalc` argv terminal launch.

- [ ] **Step 4: Verify and update parity evidence**

```bash
bash tests/direct-integrations.sh
qmltestrunner -input tests/qml/tst_full_launcher_drawers_windowinfo.qml -import src -v1
```

Expected: PASS.

- [ ] **Step 5: Commit launcher and window parity**

```bash
git add src tests
git commit -m "feat: restore launcher drawers and window parity"
```

### Task 8: Restore dashboard, sidebar, notifications, and Nexus parity

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/modules/dashboard/**`
- Modify: `src/modules/sidebar/**`
- Modify: `src/modules/notifications/**`
- Modify: `src/modules/nexus/**`
- Modify: `src/services/Players.qml`
- Modify: `src/services/Notifs.qml`
- Modify: `src/services/Nmcli.qml`
- Modify: `src/services/VPN.qml`
- Modify: `src/services/Weather.qml`
- Create: `tests/qml/tst_full_dashboard_sidebar_nexus.qml`
- Modify: `tests/parity-manifest.json`

**Interfaces:**
- Consumes: MPRIS, lyrics/artwork cache, calendar/weather, resources, notifications/history/DND, NetworkManager, Bluetooth, PipeWire, power profiles, and settings.
- Produces: complete dashboard tabs, sidebar notification dock, notification overlays/actions, and Nexus pages/dialogs.

- [ ] **Step 1: Write complete online/offline fixtures**

Test multiple players, seek/transport, delayed artist metadata, missing art and
lyrics, calendar/weather, resources, grouped notifications/actions/DND,
Wi-Fi scan/connect/hidden network/IP configuration, Ethernet, VPN,
Bluetooth device connect, output/input/app-volume control, and independent
hardware/provider degradation.

- [ ] **Step 2: Restore original module bindings and animations**

Use Quickshell native providers where upstream already supplies the exact
model. Use existing Sleepy service facades only where their exposed model is
complete. Do not render protocol-v3 placeholders when the upstream provider is
available.

- [ ] **Step 3: Preserve credential isolation**

Network secret input is sent only to a NetworkManager secret agent or protected
single-use helper. Add a test that scans process argv and captured logs for the
fixture secret and asserts zero matches.

- [ ] **Step 4: Verify the slice**

```bash
bash tests/direct-integrations.sh
qmltestrunner -input tests/qml/tst_full_dashboard_sidebar_nexus.qml -import src -v1
```

Expected: PASS.

- [ ] **Step 5: Commit dashboard/sidebar/Nexus parity**

```bash
git add src tests
git commit -m "feat: restore dashboard sidebar and Nexus parity"
```

### Task 9: Restore utilities and reproduce the lock UI on the secure locker

**Repositories:** `sleepy-desktop`, `sleepy-session`

**Files:**
- Modify: `sleepy-desktop/src/modules/utilities/**`
- Modify: `sleepy-desktop/src/modules/session/**`
- Modify: `sleepy-desktop/locker/qml/LockRoot.qml`
- Create: `sleepy-desktop/locker/qml/CaelestiaLockView.qml`
- Modify: `sleepy-desktop/locker/CMakeLists.txt`
- Modify: `sleepy-desktop/tests/locker-boundary.sh`
- Create: `sleepy-desktop/tests/qml/tst_full_utilities_session.qml`
- Modify: `sleepy-session/src/desktop/utilities.rs`
- Modify: `sleepy-session/src/desktop/mod.rs`
- Modify: `sleepy-session/tests/desktop_services.rs`

**Interfaces:**
- Consumes: screenshot/recording, idle inhibitor, game mode, session actions, redacted lock state, and native secure prompt.
- Produces: upstream-equivalent utilities/session surfaces and a visually identical lock surface whose authentication remains native and fail-secure.

- [ ] **Step 1: Write failing utility/session tests**

Cover recording start/pause/stop/list/open/delete, screenshot/selection/color
picker, idle inhibition, game mode, session confirmation animation, lock,
suspend, logout, reboot, power-off, cancellation, and operation failure.

- [ ] **Step 2: Write locker visual-interface tests**

Assert `CaelestiaLockView` receives only `inputLength`, authentication status,
clock, media, weather, notification-summary, resources, and output geometry;
reject a `password`, `text`, `unlock`, or general session socket property.

- [ ] **Step 3: Port lock visuals without the upstream PAM implementation**

Reuse the imported lock layout/components/tokens and animation values inside
the dedicated locker package. Connect the password indicators and status only
to `SecurePrompt`; do not package `src/modules/lock/Pam.qml` or upstream PAM
configuration.

- [ ] **Step 4: Fill only missing protected daemon operations**

If a utility or session operation cannot be performed safely as direct fixed
argv, add the exact typed operation to the existing Sleepy utility/session
authority and its Rust tests. Do not add an unlock command.

- [ ] **Step 5: Verify utility and lock boundaries**

```bash
cargo test --locked --manifest-path ../sleepy-session/Cargo.toml --test desktop_services
bash ../sleepy-desktop/tests/locker-boundary.sh
qmltestrunner -input ../sleepy-desktop/tests/qml/tst_full_utilities_session.qml -import ../sleepy-desktop/src -v1
nix build ../sleepy-desktop#sleepy-locker -L
```

Expected: PASS.

- [ ] **Step 6: Commit each repository independently**

```bash
git -C ../sleepy-session add src tests
git -C ../sleepy-session commit -m "feat: complete protected shell operations"
git add locker src/modules/session src/modules/utilities tests
git commit -m "feat: restore utilities session and lock parity"
```

### Task 10: Package the complete runtime and document provider ownership

**Repositories:** `sleepy-desktop`, root `sleepy`

**Files:**
- Modify: `sleepy-desktop/flake.nix`
- Modify: `sleepy-desktop/README.md`
- Create: `sleepy-desktop/tests/packaged-full-shell-smoke.sh`
- Create: `sleepy/docs/architecture/shell-runtime-integrations.md`
- Modify: `sleepy/modules/nixos/session/default.nix`
- Modify: `sleepy/modules/home/quickshell/default.nix`
- Modify: `sleepy/modules/home/session/default.nix`
- Modify: `sleepy/checks/quickshell-contract.sh`
- Modify: `sleepy/checks/component-contract-test.sh`

**Interfaces:**
- Consumes: complete desktop/locker packages and direct-integration registry.
- Produces: a closure containing every required runtime utility/font/library and an authoritative human-readable direct-vs-session ownership document.

- [ ] **Step 1: Write a failing packaged closure test**

Make `packaged-full-shell-smoke.sh` launch the installed shell from an empty
XDG home under a private Wayland compositor and assert that every active QML
component/plugin resolves. Check that the wrapper PATH contains the exact Nix
store paths for registered direct executables.

- [ ] **Step 2: Add exact runtime packages**

Package NetworkManager/`nmcli`, BlueZ tools, WirePlumber tools, brightnessctl,
power-profiles-daemon, wl-clipboard, swappy, libqalculate, ddcutil, sensors,
required fonts, Qt image formats, m3shapes, the full Sleepy plugin, and
Sleepy session binaries.

- [ ] **Step 3: Generate the ownership documentation from the registry**

Create `shell-runtime-integrations.md` with one row per feature and columns
`Feature`, `State source`, `Mutation path`, `Executable/API`, `Why direct or
session`, `Secret handling`, and `Failure behavior`. Add a test that every
registry ID appears exactly once in the document.

- [ ] **Step 4: Verify empty-home startup and root composition**

```bash
bash tests/packaged-full-shell-smoke.sh
nix build .#sleepy-shell -L
nix flake check --no-write-lock-file -L
```

Expected: PASS without network bootstrap or Caelestia runtime paths.

- [ ] **Step 5: Commit component and root changes**

```bash
git -C ../sleepy-desktop add flake.nix README.md tests
git -C ../sleepy-desktop commit -m "build: package the complete Sleepy shell runtime"
git add modules checks docs/architecture/shell-runtime-integrations.md
git commit -m "docs: define shell runtime integration ownership"
```

### Task 11: Add deterministic pixel and animation comparison

**Repositories:** `sleepy-desktop`, root `sleepy`

**Files:**
- Create: `sleepy-desktop/tests/reference/scenarios.json`
- Create: `sleepy-desktop/tests/reference/masks/sleepy-branding.json`
- Create: `sleepy-desktop/tests/reference/capture.sh`
- Create: `sleepy-desktop/tests/reference/compare.py`
- Create: `sleepy-desktop/tests/reference/test_compare.py`
- Create: `sleepy/checks/caelestia-reference-vm.nix`
- Modify: `sleepy-desktop/tests/parity-manifest.json`
- Modify: `sleepy-desktop/tests/run.sh`
- Modify: `sleepy/checks/default.nix`

**Interfaces:**
- Consumes: exact upstream v2.4.0 and Sleepy packages, deterministic fixtures, fixed monitor layouts, timestamps, and branding masks.
- Produces: paired PNG/frame sequences and JSON comparison reports for every required scenario.

- [ ] **Step 1: Test the comparator with exact synthetic fixtures**

Create Python tests for exact match, allowed branding-mask differences,
one-pixel out-of-mask failure, missing surface bounds, wrong opacity, and wrong
animation-frame count. Use Pillow/NumPy from the Nix check environment.

- [ ] **Step 2: Implement deterministic comparison outputs**

`compare.py` accepts `--reference`, `--candidate`, `--mask`, and `--report`;
reports image dimensions, differing pixels outside masks, maximum channel
delta, structural bounds, and pass/fail. Animation mode compares ordered frame
files and timestamps and fails on duration/easing-path drift.

- [ ] **Step 3: Define scenario coverage**

Include unlocked desktop, bar popouts, launcher modes, dashboard tabs, sidebar,
notification overlay, Nexus pages/dialogs, OSD kinds, session menu, utilities,
window info, wallpaper/style, secure lock, reduced motion, effects disabled,
one monitor, two monitors, mixed scale, hotplug, and fullscreen suppression.

- [ ] **Step 4: Run exact upstream and Sleepy capture guests**

The Nix VM check starts disposable private sessions with identical fixtures,
fonts, locale, clock, wallpaper, monitor geometry, and scripted inputs. It
writes only deterministic artifacts and comparison JSON.

- [ ] **Step 5: Close the parity manifest**

Replace every reachable `approved-deviation`/`deferred-environment` entry with
`verified` evidence from component, private-Wayland, reference capture, or VM
tests. Mark only validated non-runtime paths `excluded-non-runtime`.

Add `bash "$repo_root/tests/full-parity-contract.sh"` to
`sleepy-desktop/tests/run.sh` after the manifest has no reachable incomplete
entry.

- [ ] **Step 6: Run parity closure**

```bash
python3 -m unittest tests/reference/test_compare.py
bash tests/parity.sh
bash tests/full-parity-contract.sh
nix build .#checks.x86_64-linux.caelestia-reference-vm -L
```

Expected: PASS and zero reachable non-verified entries.

- [ ] **Step 7: Commit reference verification**

```bash
git -C ../sleepy-desktop add tests
git -C ../sleepy-desktop commit -m "test: prove Caelestia visual and animation parity"
git add checks
git commit -m "test: add deterministic shell reference VM"
```

### Task 12: Pin the compatible graph and run real virt-manager acceptance

**Repositories:** `sleepy-sdk`, `sleepy-session`, `sleepy-desktop`, root `sleepy`

**Files:**
- Modify: `sleepy-desktop/flake.nix`
- Modify: `sleepy/flake.nix`
- Modify: `sleepy/flake.lock`
- Modify: `sleepy/components/desktop-m2-baseline.json`
- Modify: `sleepy/docs/acceptance/hyprland-sleepy-desktop.md`
- Modify: `sleepy/docs/runbooks/sleepy-vm-hyprland.md`

**Interfaces:**
- Consumes: clean reviewed component commits and the existing libvirt `Sleepy` domain.
- Produces: immutable component pins, complete rollback evidence, and a filled real-VM acceptance record.

- [ ] **Step 1: Verify all component worktrees are clean and tested**

```bash
git -C ../sleepy-sdk status --short
git -C ../sleepy-session status --short
git -C ../sleepy-desktop status --short
cargo test --locked --manifest-path ../sleepy-session/Cargo.toml
bash ../sleepy-desktop/tests/run.sh
```

Expected: empty status and passing suites.

- [ ] **Step 2: Pin exact component commits**

Update desktop's session/SDK pins first, then root's desktop/session/SDK pins;
regenerate `flake.lock` once and verify every locked revision equals the local
reviewed commit.

- [ ] **Step 3: Run the complete immutable root graph**

Run: `nix flake check --no-write-lock-file -L`

Expected: PASS including production and reference VM checks.

- [ ] **Step 4: Create and verify the offline rollback bundle**

With the `Sleepy` domain shut down, follow
`docs/runbooks/sleepy-vm-hyprland.md` to record identity, XML, disk/backing
chain, NVRAM, checksums, and a temporary-domain restore drill. Do not modify
the protected domain until the restore drill passes.

- [ ] **Step 5: Switch and test through virt-manager**

Boot ReGreet, log in to UWSM Hyprland, and exercise the unlocked desktop, bar
popouts, launcher application/calculator/scheme/wallpaper modes, dashboard
tabs, sidebar, notification overlay, Nexus pages/dialogs, every OSD kind,
session menu, utilities, window information, wallpaper/style controls, secure
lock, reduced motion, effects disabled, one monitor, two monitors, mixed
scale, hotplug, fullscreen suppression, network/audio/portal actions,
suspend/resume, shell/daemon/locker restart recovery, and logout/login. Capture
redacted screenshots/frame sequences and journal/service evidence.

- [ ] **Step 6: Verify bootloader rollback and return**

Boot the prior Niri generation, verify essential login and legacy state hashes,
then return to the candidate Hyprland generation and repeat readiness,
full-parity, service-health, and framebuffer checks.

- [ ] **Step 7: Fill the acceptance record only from fresh evidence**

Replace every `PENDING` with PASS/FAIL and a redacted artifact hash or exact
evidence reference. Record the final acceptance decision, open failures,
rollback-bundle retention decision, evidence deletion status, and reviewer.

- [ ] **Step 8: Commit immutable pins and acceptance evidence**

```bash
git add flake.nix flake.lock components docs/acceptance docs/runbooks
git commit -m "test: record full Hyprland shell acceptance"
```

### Task 13: Final verification and technical specification handoff

**Repositories:** all four feature worktrees

**Files:**
- Modify: `sleepy-desktop/README.md`
- Modify: `sleepy-session/README.md`
- Modify: `sleepy/README.md`
- Modify: `sleepy/docs/architecture/shell-runtime-integrations.md`

**Interfaces:**
- Consumes: final packages, registries, tests, comparison reports, VM evidence, and immutable pins.
- Produces: complete operator/developer documentation and a review-ready branch set.

- [ ] **Step 1: Document how the shell works**

Explain startup, module graph, settings, direct Quickshell services,
`hyprctl`, `nmcli`, other fixed utilities, Sleepy Session operations,
secure-lock boundary, state reconciliation, failure modes, customization,
upstream provenance/update procedure, tests, and VM acceptance commands.

- [ ] **Step 2: Cross-check documentation against executable registries**

Run the ownership-document test and assert every direct integration and every
Sleepy Session operation appears exactly once with its state and mutation
path.

- [ ] **Step 3: Run final component verification**

```bash
cargo fmt --check --manifest-path ../sleepy-session/Cargo.toml
cargo clippy --locked --all-targets --manifest-path ../sleepy-session/Cargo.toml -- -D warnings
cargo test --locked --manifest-path ../sleepy-session/Cargo.toml
bash ../sleepy-desktop/tests/run.sh
nix flake check --no-write-lock-file -L
```

Expected: all commands PASS from clean worktrees.

- [ ] **Step 4: Verify repository cleanliness and pins**

```bash
for repo in ../sleepy-sdk ../sleepy-session ../sleepy-desktop .; do
  git -C "$repo" status --short
  git -C "$repo" log -1 --oneline
done
```

Expected: no uncommitted files and root/desktop locks point to the displayed
component commits.

- [ ] **Step 5: Commit final documentation**

```bash
git -C ../sleepy-session add README.md
git -C ../sleepy-session commit -m "docs: explain shell session ownership"
git -C ../sleepy-desktop add README.md
git -C ../sleepy-desktop commit -m "docs: explain the full modular shell"
git add README.md docs/architecture/shell-runtime-integrations.md
git commit -m "docs: publish the Sleepy shell technical specification"
```

- [ ] **Step 6: Perform completion review**

Compare every completion criterion in the spec to a passing command or VM
evidence reference. Do not claim completion while any reachable parity entry,
reference comparison, automated check, or real virt-manager row is incomplete.
