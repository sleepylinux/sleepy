# Sleepy Desktop Milestone 2 Control Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a real, polished glass Control Center with coherent icons, confirmed system controls, durable named presets, and freely editable conflict-safe Niri bindings.

**Architecture:** Public JSON and accelerator contracts land in `sleepy-sdk`; durable mutations, system adapters, and binding compilation live in `sleepy-session`; logical SVG assets live in `sleepy-artwork`; Quickshell views consume typed snapshots and semantic actions in `sleepy-desktop`; the root distribution pins reviewed revisions and owns NixOS/Home Manager/Niri integration. Each component is independently tested and committed before the root pin advances.

**Tech Stack:** Rust 2021, serde/serde_json, UUID, Qt 6 QML/Qt Test, Quickshell, Nix flakes, Home Manager, Niri KDL, Bash contract tests.

**Spec:** `docs/superpowers/specs/2026-08-24-desktop-m2-control-center-design.md`

## Global Constraints

- Branches use `feat/` or `chore/`; never use `codex/`.
- Sleepy-owned source and packages are `GPL-3.0-only`; unrelated dependencies may retain their own licenses.
- Keep JSON `schemaVersion: 1` for this milestone and do not silently rewrite existing state.
- Home Manager must never own or overwrite `settings.json`, `presets.json`, or the generated user binding include.
- Every production behavior begins with a failing test and recorded RED evidence.
- Built-in presets are immutable; every editable copy is a user UUID preset.
- System commands use fixed executable/argument arrays, explicit timeouts, and no shell interpolation.
- UI state changes only after a valid snapshot or confirmed mutation readback.
- Functional icons are logical SVG assets, not Unicode glyphs.
- Full/reduced/none effects must preserve readable contrast; reduced motion removes non-essential animation.
- No generation deletion, garbage collection, credential recording, or destructive user-state cleanup is permitted.

---

### Task 1: SDK accelerator and system document contracts

**Repository:** `sleepy-sdk`

**Files:**
- Create: `src/keybindings.rs`
- Create: `src/system.rs`
- Create: `fixtures/v1/preset/valid-bindings.json`
- Create: `fixtures/v1/preset/invalid-duplicate-binding.json`
- Create: `fixtures/v1/system/valid.json`
- Create: `fixtures/v1/system/invalid-unknown-field.json`
- Modify: `src/lib.rs`
- Modify: `src/bin/sleepy-contract.rs`
- Modify: `schemas/preset.schema.json`
- Create: `schemas/system.schema.json`
- Modify: `tests/contracts.rs`
- Modify: `tests/schemas.rs`
- Modify: `tests/cli.rs`

**Interfaces:**
- Produces `canonicalize_accelerator(&str) -> Result<String, ContractError>`.
- Produces `validate_keybindings(&BTreeMap<String, String>) -> Result<(), ContractError>`.
- Produces strict serde types `SystemSnapshot`, `CapabilityState`, `NetworkState`, `BluetoothState`, `AudioState`, `DisplayState`, `PowerState`, and `MediaState`.
- Produces `validate_system_snapshot(&str) -> Result<SystemSnapshot, ContractError>` and CLI kind `system`.

- [ ] **Step 1: Write accelerator RED tests**

Add tests that require `shift+mod+d` to canonicalize to `Mod+Shift+D`; reject duplicate/unknown modifiers, zero or two keys, blank action identifiers, and canonical duplicate chords assigned to two actions.

- [ ] **Step 2: Run accelerator RED**

Run: `cargo test --test contracts keybinding -- --nocapture`

Expected: compile failure because `canonicalize_accelerator` and `validate_keybindings` do not exist.

- [ ] **Step 3: Implement the minimal accelerator parser**

Use this public shape:

```rust
pub fn canonicalize_accelerator(input: &str) -> Result<String, ContractError>;
pub fn validate_keybindings(
    bindings: &BTreeMap<String, String>,
) -> Result<(), ContractError>;
```

Accept case-insensitive `Mod|Ctrl|Alt|Shift`, emit them in that exact order,
require one nonblank key, and compare canonical strings for conflicts.

- [ ] **Step 4: Write system-document RED tests**

Require a complete valid fixture with a capabilities map and nullable hardware
states; reject unknown fields, out-of-range normalized levels, and capability
values other than `available|unavailable|busy|error`.

- [ ] **Step 5: Run system-document RED**

Run: `cargo test --test contracts system_snapshot -- --nocapture`

Expected: compile failure because system types and validator do not exist.

- [ ] **Step 6: Implement strict system types and schema**

Use normalized `f64` values constrained to `0.0..=1.0`, optional battery and
brightness fields, and `deny_unknown_fields` on every public document type.
Add `sleepy-contract validate system <path>`.

- [ ] **Step 7: Verify Task 1**

Run:

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
nix flake check -L
```

Expected: all Rust tests and the component flake check pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add src schemas fixtures tests
git commit -m "feat: add control center contracts"
```

### Task 2: Session preset mutation, import, export, and CLI

**Repository:** `sleepy-session`

**Files:**
- Create: `src/store/presets.rs`
- Create: `src/store/import_export.rs`
- Create: `src/cli.rs`
- Modify: `src/store/state.rs`
- Modify: `src/store/error.rs`
- Modify: `src/store/mod.rs`
- Modify: `src/bin/sleepyctl.rs`
- Modify: `tests/store.rs`
- Modify: `tests/cli.rs`
- Modify: `tests/flake.rs`

**Interfaces:**
- Consumes Task 1 SDK revision and `validate_keybindings`.
- Produces `preset_json`, `active_preset_json`, `update_user_preset`, `delete_user_preset`, `export_preset`, `import_preset`, and `validate_preset_candidate`.
- Produces CLI commands `presets show|create|update|delete|validate|import|export` and `keybindings list|set|unset|validate`.

- [ ] **Step 1: Pin the reviewed Task 1 SDK revision and write store RED tests**

Tests must prove complete-field update, immutable rejection for every mutation,
active-delete rejection, ID-conflict rejection, built-in import-as-copy,
explicit user replace, invalid import byte preservation, duplicate-name
acceptance, and concurrent update serialization.

- [ ] **Step 2: Run store RED**

Run: `cargo test --test store preset_mutation -- --nocapture`

Expected: compile failures for the missing store methods.

- [ ] **Step 3: Implement atomic preset operations**

Use this public API:

```rust
pub enum ImportMode { Reject, Copy, Replace }
pub fn preset_json(&self, id: &str) -> Result<Value, StoreError>;
pub fn active_preset_json(&self) -> Result<Value, StoreError>;
pub fn update_user_preset(&self, id: &str, candidate: Value) -> Result<Value, StoreError>;
pub fn delete_user_preset(&self, id: &str) -> Result<Value, StoreError>;
pub fn export_preset(&self, id: &str) -> Result<Value, StoreError>;
pub fn import_preset(&self, candidate: Value, mode: ImportMode) -> Result<Value, StoreError>;
pub fn validate_preset_candidate(&self, candidate: Value) -> Result<Value, StoreError>;
```

Resolve origin before every mutation, validate the whole candidate, then reuse
the existing locked atomic collection replacement.

- [ ] **Step 4: Write CLI RED tests**

Cover file and `-` stdin input, stdout export round trip, structured conflict
errors, invalid command non-initialization, and successful binding set/unset.

- [ ] **Step 5: Run CLI RED**

Run: `cargo test --test cli -- --nocapture`

Expected: failures because the new subcommands are absent.

- [ ] **Step 6: Implement a parsed CLI command layer**

Move argument interpretation into `src/cli.rs`; keep `main` limited to JSON
output and structured JSON error rendering. File input must reject symlinks and
read bounded UTF-8 JSON.

- [ ] **Step 7: Verify Task 2**

Run:

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo build --release
```

- [ ] **Step 8: Commit Task 2**

```bash
git add Cargo.toml Cargo.lock src tests flake.nix
git commit -m "feat: add editable preset operations"
```

### Task 3: Binding compiler and safe Niri application

**Repository:** `sleepy-session`

**Files:**
- Create: `src/bindings/mod.rs`
- Create: `src/bindings/actions.rs`
- Create: `src/bindings/compiler.rs`
- Create: `src/bindings/apply.rs`
- Create: `tests/bindings.rs`
- Create: `tests/fixtures/bindings/expected.kdl`
- Modify: `src/lib.rs`
- Modify: `src/cli.rs`
- Modify: `tests/cli.rs`

**Interfaces:**
- Consumes Task 2 active preset API and Task 1 canonical accelerators.
- Produces `compile_bindings(&PresetDocument) -> Result<String, BindingError>`.
- Produces `apply_active_bindings(paths, validator, reloader) -> Result<ApplyReport, BindingError>`.
- Produces `sleepyctl bindings render` and `sleepyctl bindings apply`.

- [ ] **Step 1: Write compiler RED tests**

Golden tests must map semantic actions to exact Niri KDL actions, sort output
deterministically, escape string arguments, reject unknown semantic actions,
and never emit shell command strings.

- [ ] **Step 2: Run compiler RED**

Run: `cargo test --test bindings compiler -- --nocapture`

Expected: compile failure because the bindings module is absent.

- [ ] **Step 3: Implement action registry and compiler**

Represent packaged actions as a closed Rust match from semantic identifier to
typed KDL statement. Include terminal, launcher, close, focus, workspace,
Control Center, session, media, volume, and brightness actions.

- [ ] **Step 4: Write safe-application RED tests**

Inject a validator and reloader. Prove candidate validation happens before
replacement, replacement is atomic, failed validation/reload retains the last
valid include, and the report distinguishes `validated`, `installed`, and
`reloadConfirmed`.

- [ ] **Step 5: Run safe-application RED**

Run: `cargo test --test bindings apply -- --nocapture`

Expected: failures for missing apply API.

- [ ] **Step 6: Implement application and CLI**

Write a same-directory candidate, compose it with static Niri fixtures for
validation, atomically replace only after success, request Niri reload, and
return structured JSON. Preserve the previous include as the active file on
every pre-replacement failure.

- [ ] **Step 7: Verify and commit Task 3**

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
git add src tests
git commit -m "feat: compile and apply user bindings"
```

### Task 4: Typed real-system adapter facade

**Repository:** `sleepy-session`

**Files:**
- Create: `src/system/mod.rs`
- Create: `src/system/runner.rs`
- Create: `src/system/network.rs`
- Create: `src/system/bluetooth.rs`
- Create: `src/system/audio.rs`
- Create: `src/system/display.rs`
- Create: `src/system/power.rs`
- Create: `src/system/media.rs`
- Create: `tests/system.rs`
- Create: `tests/fixtures/system/`
- Modify: `src/cli.rs`
- Modify: `src/bin/sleepyctl.rs`

**Interfaces:**
- Consumes Task 1 `SystemSnapshot`.
- Produces `SystemFacade<R: CommandRunner>::snapshot()` and
  `mutate(capability, value)`.
- Produces `sleepyctl system show` and `sleepyctl system set`.

- [ ] **Step 1: Write parser and runner RED tests**

Fixtures cover valid, unsupported, malformed, nonzero, and timeout results for
nmcli, bluetoothctl, wpctl, brightnessctl, powerprofilesctl, UPower, and
playerctl. Tests assert fixed executable/argument arrays.

- [ ] **Step 2: Run parser RED**

Run: `cargo test --test system -- --nocapture`

Expected: compile failure because `SystemFacade` is absent.

- [ ] **Step 3: Implement bounded command runner and pure parsers**

Use explicit timeouts, capped stdout/stderr, no shell, locale-stable arguments,
and individual capability errors. Assemble one valid snapshot even when some
hardware is unsupported.

- [ ] **Step 4: Write mutation/readback RED tests**

Prove each mutation uses the expected command and returns state from a fresh
readback. Failed mutation/readback must not fabricate optimistic state.

- [ ] **Step 5: Implement mutations and CLI**

Accept only typed boolean, normalized-level, enum-profile, or transport action
values allowed by the capability registry. Return structured unsupported,
busy, timeout, command, and parse errors.

- [ ] **Step 6: Verify and commit Task 4**

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo build --release
git add src tests Cargo.toml Cargo.lock
git commit -m "feat: add control center system adapters"
```

### Task 5: Logical Control Center icon set

**Repository:** `sleepy-artwork`

**Files:**
- Create: `icons/control-center.svg`
- Create: `icons/network.svg`
- Create: `icons/bluetooth.svg`
- Create: `icons/volume.svg`
- Create: `icons/microphone.svg`
- Create: `icons/brightness.svg`
- Create: `icons/night-light.svg`
- Create: `icons/focus.svg`
- Create: `icons/battery.svg`
- Create: `icons/power-profile.svg`
- Create: `icons/media-play.svg`
- Create: `icons/media-pause.svg`
- Create: `icons/media-next.svg`
- Create: `icons/media-previous.svg`
- Create: `icons/lock.svg`
- Create: `icons/logout.svg`
- Create: `icons/power.svg`
- Create: `icons/preset.svg`
- Create: `icons/keybinding.svg`
- Modify: `branding/manifest.json`
- Modify: `flake.nix`
- Modify: `tests/manifest.sh`
- Modify: `README.md`

**Interfaces:**
- Produces logical names `icons.<name>` resolving to package-relative SVGs.
- Every SVG uses `currentColor`, a consistent 24×24 viewBox, round line caps,
  and no embedded text, raster data, script, or external reference.

- [ ] **Step 1: Write manifest/SVG RED tests**

Require every logical name, file existence, 24×24 viewBox, `currentColor`, and
absence of external URLs, scripts, embedded raster images, or Unicode text.

- [ ] **Step 2: Run artwork RED**

Run: `bash tests/manifest.sh`

Expected: failure listing missing Control Center icon entries.

- [ ] **Step 3: Add the coherent GPL SVG set and package installation**

Draw simple two-pixel rounded strokes with consistent optical weight. Install
the icon directory beside the existing branding manifest and primary mark.

- [ ] **Step 4: Verify and commit Task 5**

```bash
bash tests/manifest.sh
bash tests/license.sh
nix flake check -L
git add icons branding flake.nix tests README.md
git commit -m "feat: add control center icon set"
```

### Task 6: Desktop material, icon, and generic surface foundation

**Repository:** `sleepy-desktop`

**Files:**
- Create: `src/theme/EffectsPolicy.qml`
- Create: `src/widgets/GlassSurface.qml`
- Create: `src/widgets/SleepyIcon.qml`
- Create: `src/services/IconRegistry.qml`
- Create: `src/services/SurfaceRegistry.qml`
- Create: `src/surfaces/DrawerFrame.qml`
- Create: `src/surfaces/DrawerHeader.qml`
- Modify: `src/theme/Palette.qml`
- Modify: `src/theme/ThemeTokens.qml`
- Modify: `src/services/SurfaceController.qml`
- Modify: `src/services/SurfaceWindowPolicy.qml`
- Modify: `src/panels/ShellGeometry.qml`
- Modify: `src/panels/RailView.qml`
- Modify: `src/shell.qml`
- Create: `tests/qml/tst_materials.qml`
- Create: `tests/qml/tst_icons.qml`
- Create: `tests/qml/tst_surface_registry.qml`
- Modify: `tests/qml/tst_geometry.qml`
- Modify: `tests/qml/tst_window_policy.qml`

**Interfaces:**
- Consumes Task 5 logical artwork manifest.
- Produces `EffectsPolicy`, `GlassSurface`, `IconRegistry.sourceFor(name)`,
  `SleepyIcon`, and descriptor records with `id`, `edge`, `width`,
  `triggerIcon`, `triggerLabel`, and `initialFocusTarget`.

- [ ] **Step 1: Write material/icon RED tests**

Assert full/reduced/none alpha, contrast fallback, shadow/glow policy, zero
motion under reduced motion, complete icon resolution, and no functional
Unicode glyph properties in interactive widgets.

- [ ] **Step 2: Run material/icon RED**

Run: `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software bash tests/run.sh`

Expected: missing-type failures for EffectsPolicy and IconRegistry.

- [ ] **Step 3: Implement material and icon primitives**

Use layered rectangles/gradients and explicit opacity roles; keep the outer
PanelWindow transparent. The no-effects policy must force opaque surfaces.

- [ ] **Step 4: Write generic surface RED tests**

Test left/right geometry, variable widths, one-open semantics, screen scoping,
descriptor-driven triggers, initial focus, Escape, and focus restoration.

- [ ] **Step 5: Implement registry/frame refactor**

Register `controlCenter` through a descriptor and keep the M1 compatibility
methods until the Control Center view lands.

- [ ] **Step 6: Verify and commit Task 6**

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software bash tests/run.sh
bash scripts/validate-qml.sh
bash tests/dependencies.sh
git add src tests flake.nix README.md
git commit -m "feat: add glass surface foundation"
```

### Task 7: Desktop real Control Center and settings management

**Repository:** `sleepy-desktop`

**Files:**
- Create: `src/services/SystemAdapterCore.qml`
- Create: `src/services/SystemAdapter.qml`
- Create: `src/services/PresetAdapterCore.qml`
- Create: `src/services/PresetAdapter.qml`
- Create: `src/services/ActionRegistry.qml`
- Create: `src/services/ShortcutRouter.qml`
- Create: `src/widgets/IconButton.qml`
- Create: `src/widgets/CompactToggle.qml`
- Create: `src/widgets/LevelControl.qml`
- Create: `src/widgets/InfoChip.qml`
- Create: `src/widgets/MediaCard.qml`
- Create: `src/widgets/DeviceRow.qml`
- Create: `src/widgets/PresetRow.qml`
- Create: `src/widgets/BindingRow.qml`
- Create: `src/drawers/ControlCenterDrawer.qml`
- Create: `src/drawers/ControlCenterView.qml`
- Create: `src/drawers/PresetManagerView.qml`
- Create: `src/drawers/BindingEditorView.qml`
- Modify: `src/shell.qml`
- Modify: `src/panels/RailView.qml`
- Modify: `src/preview/main.qml`
- Create: `tests/qml/tst_system_adapter.qml`
- Create: `tests/qml/tst_preset_adapter.qml`
- Create: `tests/qml/tst_control_center.qml`
- Create: `tests/qml/tst_keyboard_navigation.qml`
- Create: `tests/qml/tst_accessibility.qml`

**Interfaces:**
- Consumes Task 2–4 `sleepyctl` JSON and Task 6 UI primitives.
- Produces valid last-known system state, capability busy/error state, preset
  CRUD/import/export flows, binding conflict UX, and a complete Control Center.

- [ ] **Step 1: Write adapter RED tests**

Test valid snapshots, malformed/unknown output, timeout/nonzero exit, last-valid
preservation, immediate refresh after mutation, no optimistic updates, preset
CRUD, immutable built-in behavior, and structured conflicts.

- [ ] **Step 2: Run adapter RED**

Run: `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software bash tests/run.sh`

Expected: missing SystemAdapterCore and PresetAdapterCore types.

- [ ] **Step 3: Implement process wrappers and pure cores**

Keep parsing/state transitions in testable QtObjects. Quickshell Process wrappers
only launch fixed `sleepyctl` arrays and feed exit/output events to the cores.

- [ ] **Step 4: Write Control Center view RED tests**

Test compact/tall overflow, fixture-driven sections, unsupported controls,
busy indicators, page navigation, initial focus, arrows, Tab/Home/End, Escape,
disabled-item skipping, accessible names/roles, and focus return.

- [ ] **Step 5: Implement the dense glass Control Center**

Use a Flickable page stack and the exact sections from the spec. Remove the M1
Unicode controls and retire `QuickSettingsView` only after compatibility tests
move to `ControlCenterView`.

- [ ] **Step 6: Expand the preview gallery**

Provide deterministic full/reduced/none, dark/light, 1280×800, compact, preset
list, and conflict-state scenes without writing user state.

- [ ] **Step 7: Verify and commit Task 7**

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software bash tests/run.sh
bash scripts/validate-qml.sh
bash tests/dependencies.sh
git add src tests flake.nix README.md
git commit -m "feat: ship the Sleepy control center"
```

### Task 8: Root NixOS, Home Manager, Niri, and CI integration

**Repository:** `sleepy`

**Files:**
- Modify: `flake.nix`
- Modify: `components/desktop-m1.json`
- Modify: `overlays/default.nix`
- Modify: `modules/nixos/base/default.nix`
- Modify: `modules/home/session/default.nix`
- Modify: `modules/home/niri/default.nix`
- Modify: `modules/home/niri/config/config.kdl`
- Rename: `modules/home/niri/config/bindings.kdl` to `bindings-core.kdl`
- Modify: `modules/home/quickshell/default.nix`
- Modify: `checks/default.nix`
- Create: `checks/bindings-contract.nix`
- Create: `checks/control-center-contract.nix`
- Modify: `checks/update-safety.nix`
- Modify: `checks/update-safety-contract.sh`
- Modify: `checks/component-contract.sh`
- Modify: `.github/workflows/check.yml`

**Interfaces:**
- Consumes reviewed Task 1–7 component revisions.
- Produces enabled adapter services/tools, component-owned checks, immutable
  core bindings, a user-owned generated include, and keyboard Control Center
  activation.

- [ ] **Step 1: Write root contract RED tests**

Require BlueZ/power-profile capability wiring, external component checks,
static core include plus generated user include, no Home Manager ownership of
the generated file, stable settings/presets/bindings hashes, and a default
semantic Control Center bind.

- [ ] **Step 2: Run root RED**

Run:

```bash
bash checks/update-safety-contract-test.sh
bash checks/component-contract-test.sh
nix build .#checks.x86_64-linux.bindings-contract -L
```

Expected: failures for missing includes, services, and external checks.

- [ ] **Step 3: Implement Nix and binding ownership changes**

Home Manager owns `bindings-core.kdl`; session initialization creates the
generated include only if absent, then `sleepyctl bindings apply` owns updates.
Wire tools and services explicitly without making hardware availability a
build-time assertion.

- [ ] **Step 4: Pin reviewed component commits and regenerate lock**

Run `nix flake lock`, inspect every Sleepy node against the manifest, and never
hand-edit `narHash` values.

- [ ] **Step 5: Run full root verification**

```bash
for test_script in checks/*-test.sh; do bash "$test_script"; done
nix flake check -L --no-write-lock-file
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel --no-link -L
nix build '.#homeConfigurations."lazy@sleepy-vm".activationPackage' --no-link -L
git diff --check
```

- [ ] **Step 6: Commit Task 8**

```bash
git add flake.nix flake.lock components overlays modules checks .github
git commit -m "feat: integrate the Sleepy control center"
```

### Task 9: VM deployment and visual acceptance

**Repository:** `sleepy`

**Files:**
- Modify: `docs/acceptance/desktop-foundation.md`
- Modify: `docs/deployment.md`
- Modify: `docs/recovery.md`
- Modify: `.superpowers/sdd/2026-08-24-desktop-m1/progress.md`

**Interfaces:**
- Consumes the exact clean Task 8 archive and built toplevel.
- Produces an accepted VM generation, preserved state hashes, screenshots, and
  factual deployment evidence.

- [ ] **Step 1: Capture immutable pre-deployment evidence**

Record runtime/profile/generation set, root-owned source hash, and metadata plus
SHA-256 for settings, presets, and generated bindings. Do not record contents.

- [ ] **Step 2: Run clean archive and full VM build gates**

Validate archive members, source-clean, component-lock, full flake check,
component outputs, Home Manager activation, and the exact NixOS toplevel.

- [ ] **Step 3: Perform reviewed dry/test activation**

Require unchanged permanent profile/generations/user-state hashes, SSH
reconnect, active graphical services, real adapter snapshot, and binding
compiler validation before permanent switch.

- [ ] **Step 4: Perform live interaction and visual acceptance**

Use the keyboard binding and mouse to open the Control Center, mutate one safe
reversible control with confirmed readback, close with Escape, exercise preset
and conflict pages, and capture the required full/no-effects and compact scenes.

- [ ] **Step 5: Perform reviewed permanent switch**

Preserve the previous `/etc/sleepy`, add exactly one expected generation, keep
all predecessors, verify runtime/profile/services/state, and retain rollback
evidence. Do not delete or garbage-collect.

- [ ] **Step 6: Update evidence, verify, commit, and push**

```bash
for test_script in checks/*-test.sh; do bash "$test_script"; done
bash checks/component-lock.sh components/desktop-m1.json flake.lock
bash checks/source-clean.sh .
git diff --check
git add docs .superpowers/sdd/2026-08-24-desktop-m1/progress.md
git commit -m "docs: record control center VM acceptance"
git push origin feat/desktop-m2-control-center
```
