# Hyprland Sleepy Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Sleepy-branded Hyprland desktop with Caelestia Shell v2.4.0 visual behavior, while `sleepy-sessiond` remains the single authority for system state and actions and ReGreet remains the login manager.

**Architecture:** Import only the GPLv3 Caelestia Shell source at its verified v2.4.0 commit into `sleepy-desktop`, rename its product boundary, and replace its service layer with a versioned Sleepy desktop protocol. Implement system, compositor, persistence, and policy services in `sleepy-session`; keep presentation and narrowly scoped compositor-connected rendering helpers in `sleepy-desktop`; compose the session with Hyprland and UWSM in root NixOS/Home Manager modules.

**Tech Stack:** Rust 2021, Tokio, serde/JSON, Unix sockets, D-Bus, systemd `sd_notify`, Hyprland IPC, Qt 6, Quickshell/QML/C++, CMake/Ninja, Nix flakes, Home Manager, UWSM, ReGreet, libvirt/QEMU/SPICE.

**Spec:** `docs/superpowers/specs/2026-08-30-hyprland-sleepy-desktop-design.md`

## Global Constraints

- Work on `feat/hyprland-sleepy-desktop`; never use a `codex/` branch prefix.
- Fork only `caelestia-dots/shell` v2.4.0 commit `24aa15eefdb146350d2548c0a015b04eddbd1008`; do not copy files from the unlicensed `caelestia-dots/caelestia` repository.
- Preserve GPLv3 notices, modification dates, corresponding source, build scripts, and a machine-readable provenance inventory.
- Runtime product names, units, paths, QML namespaces, commands, and labels are Sleepy; legal credits remain accurate and accessible.
- `sleepy-sessiond` owns system observation, persistence, policy, Hyprland IPC, and mutations. QML must not execute system command-line tools.
- Keep existing wire-v2 sockets operational during migration. Add desktop protocol v3 without silently changing a strict v2 document.
- Runtime directory mode is 0700; sockets are 0600; verify `SO_PEERCRED`; bound clients, frames, queues, reads, writes, and subprocesses.
- ReGreet remains enabled; autologin remains disabled; UWSM owns the Hyprland graphical-session lifecycle.
- The general IPC exposes `lock`, never `unlock`; only `sleepy-locker` may authenticate and issue Wayland unlock.
- Preserve legacy Sleepy state byte-for-byte and retain prior-generation boot and VM rollback paths.
- The root repository pins only mutually compatible reviewed component revisions.

---

### Task 1: Create isolated component branches and record the upstream inventory

**Repositories:** `sleepy-sdk`, `sleepy-session`, `sleepy-desktop`, root `sleepy`

**Files:**
- Create: `sleepy-desktop/UPSTREAM.json`
- Create: `sleepy-desktop/NOTICE`
- Create: `sleepy-desktop/scripts/import-upstream.sh`
- Create: `sleepy-desktop/tests/upstream-provenance.sh`
- Modify: `sleepy-desktop/tests/run.sh`

**Interfaces:**
- Consumes: verified Git tag object `15c41f3e19818199f653aa7dcec81d49affd7152` and commit `24aa15eefdb146350d2548c0a015b04eddbd1008`.
- Produces: deterministic `UPSTREAM.json`, `NOTICE`, and an importer that refuses every unapproved repository/revision.

- [ ] **Step 1: Create linked worktrees for the three component repositories**

Run from `/home/lazy/Projects/WORK/sleepy`:

```bash
mkdir -p .worktrees/hyprland-sleepy-desktop
for repo in sleepy-sdk sleepy-session sleepy-desktop; do
  git -C "$repo" worktree add \
    "$PWD/.worktrees/hyprland-sleepy-desktop/$repo" \
    -b feat/hyprland-sleepy-desktop
done
```

Expected: each worktree reports a new `feat/hyprland-sleepy-desktop` branch from `main` and `git status --short` is empty.

- [ ] **Step 2: Write the failing provenance test**

Create `tests/upstream-provenance.sh` with assertions for exact source, tag object, commit, shell license, Quickshell revision/hash, m3shapes revision/hash, and a negative assertion for `caelestia-dots/caelestia`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
jq -e '
  .source.repository == "https://github.com/caelestia-dots/shell" and
  .source.tag == "v2.4.0" and
  .source.tagObject == "15c41f3e19818199f653aa7dcec81d49affd7152" and
  .source.commit == "24aa15eefdb146350d2548c0a015b04eddbd1008" and
  .source.license == "GPL-3.0-only" and
  .dependencies.quickshell.rev == "0fed22a2c47d9568ddf13cf61586b3f2ac4378a2" and
  .dependencies.m3shapes.rev == "32ad9ce328bb77ed349b40a3be10ee9ea610b8ab"
' "$root/UPSTREAM.json" >/dev/null
! rg -n 'caelestia-dots/caelestia' "$root/src" "$root/UPSTREAM.json"
rg -F 'Caelestia Shell' "$root/NOTICE" >/dev/null
```

- [ ] **Step 3: Run the provenance test to verify it fails**

Run: `bash tests/upstream-provenance.sh`

Expected: FAIL because `UPSTREAM.json` and `NOTICE` do not exist.

- [ ] **Step 4: Implement the inventory and guarded importer**

Use `UPSTREAM.json` as the machine-readable format and make
`scripts/import-upstream.sh` accept exactly `--source "$verified_shell_checkout"`;
verify `git rev-parse HEAD`, `git describe --exact-match`, and the GPL file
before copying the approved `components`, `modules`, `services`, `plugin`,
`extras`, `assets`, `utils`, `shell.qml`, `CMakeLists.txt`, and `LICENSE` paths.
Reject a dirty source checkout. Do not perform network access inside the
importer.

- [ ] **Step 5: Run the provenance test and shell syntax check**

Run:

```bash
bash -n scripts/import-upstream.sh tests/upstream-provenance.sh
bash tests/upstream-provenance.sh
```

Expected: PASS and no unlicensed dots path in imported source.

- [ ] **Step 6: Commit the provenance boundary**

```bash
git add UPSTREAM.json NOTICE scripts/import-upstream.sh tests/upstream-provenance.sh tests/run.sh
git commit -m "build: define Caelestia shell provenance"
```

### Task 2: Define the desktop protocol v3 contracts

**Repository:** `sleepy-sdk`

**Files:**
- Create: `src/desktop_runtime.rs`
- Create: `schemas/desktop-event-v3.schema.json`
- Create: `schemas/desktop-command-v3.schema.json`
- Create: `tests/desktop_runtime.rs`
- Create: `fixtures/desktop-runtime/full-snapshot.json`
- Create: `fixtures/desktop-runtime/command.json`
- Modify: `src/lib.rs`
- Modify: `tests/schemas.rs`

**Interfaces:**
- Consumes: existing `EventCause`, `CapabilityAvailability`, notification, launcher, calendar, weather, theme, and system domain types.
- Produces: `DESKTOP_WIRE_VERSION`, `DesktopEnvelope`, `DesktopSnapshot`, `DesktopEvent`, `DesktopRequest`, `DesktopCommand`, `DesktopResult`, and strict validators.

- [ ] **Step 1: Write failing round-trip and rejection tests**

Define tests that parse the fixture and assert:

```rust
let envelope = validate_desktop_envelope(include_str!(
    "fixtures/desktop-runtime/full-snapshot.json"
))?;
assert_eq!(envelope.schema_version, DESKTOP_WIRE_VERSION);
assert!(matches!(envelope.payload, DesktopEvent::FullSnapshot(_)));
assert!(validate_desktop_request(include_str!(
    "fixtures/desktop-runtime/command.json"
)).is_ok());
assert!(validate_desktop_request(r#"{"schemaVersion":3,"extra":true}"#).is_err());
```

Also reject zero generations, noncanonical UUIDs, empty IDs, non-finite/unnormalized levels, duplicate stable IDs, secret-bearing fields named `password`, and an `Unlock` command (which must not exist).

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `cargo test --locked --test desktop_runtime`

Expected: FAIL with unresolved `desktop_runtime` exports.

- [ ] **Step 3: Implement strict v3 types**

Set `DESKTOP_WIRE_VERSION: u32 = 3`. Define `DesktopSnapshot` with exact topic
fields `system`, `compositor`, `notifications`, `launcher`, `calendar`,
`weather`, `appearance`, `resources`, and `utilities`. Define stable typed
records for monitors, workspaces, windows, network access points/connections,
Bluetooth devices, audio nodes/streams, players, resource samples, tray
items/menus, clipboard entries, recording state, and lock state. Every struct
uses `#[serde(rename_all = "camelCase", deny_unknown_fields)]`. Validators
enforce unique non-empty stable IDs and these maxima: 64 monitors, 1,024
workspaces, 16,384 windows, 4,096 access points, 1,024 Bluetooth devices, 4,096
audio nodes, 16,384 audio streams, 256 media players, 1,024 tray items, 65,536
menu nodes total, 500 clipboard entries, and 500 active notifications.

Define command families:

```rust
pub enum DesktopCommand {
    System(SystemMutation),
    Compositor(HyprlandCommand),
    Notification(NotificationCommand),
    Launcher(LauncherCommand),
    Appearance(AppearanceCommand),
    Utility(UtilityCommand),
    Session(DesktopSessionCommand),
}

pub enum DesktopSessionCommand {
    Lock,
    Suspend,
    Logout,
    Reboot,
    PowerOff,
}
```

Do not define `Unlock`. Secret submission is a different one-shot document with no serialization into snapshots or event envelopes.

- [ ] **Step 4: Generate and validate JSON schemas**

Write schemas that use `additionalProperties: false`, numeric/string/array bounds matching Rust, and exhaustive tagged enum alternatives. Add fixture validation to `tests/schemas.rs`.

- [ ] **Step 5: Run SDK verification**

```bash
cargo fmt --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked
```

Expected: all checks PASS.

- [ ] **Step 6: Commit protocol v3**

```bash
git add src/lib.rs src/desktop_runtime.rs schemas tests fixtures
git commit -m "feat: define Sleepy desktop protocol v3"
```

### Task 3: Add a bounded socket supervisor and daemon readiness

**Repository:** `sleepy-session`

**Files:**
- Create: `src/sessiond/supervisor.rs`
- Create: `tests/socket_supervisor.rs`
- Modify: `src/sessiond/mod.rs`
- Modify: `src/sessiond/socket.rs`
- Modify: `src/sessiond/control_socket.rs`
- Modify: `src/bin/sleepy-sessiond.rs`
- Modify: `Cargo.toml`

**Interfaces:**
- Consumes: Tokio `JoinSet`, `Semaphore`, Unix peer credentials, cancellation token.
- Produces: `SocketSupervisor::serve`, `ConnectionLimits`, `ConnectionContext`, bounded shutdown, and `READY=1` after all listeners are bound.

- [ ] **Step 1: Write failing supervisor tests**

Cover 32 stream clients, rejection of client 33 within 250 ms, 16 request clients, frame limit 1 MiB, read/write timeout 5 s, peer UID mismatch, task cleanup, and 10 s bounded drain. Assert file-descriptor count returns to baseline after 1,000 reconnects.

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cargo test --locked --test socket_supervisor`

Expected: FAIL because `sessiond::supervisor` is absent.

- [ ] **Step 3: Implement the common supervisor**

Use `JoinSet` to reap every completed connection, a nonblocking semaphore permit acquired before task spawn, `SO_PEERCRED` UID verification, `tokio::time::timeout` around reads and writes, and a cancellation-aware drain. Oversized frames close the client without allocation growth. Log only endpoint kind, peer PID/UID, reason code, and counts.

```rust
pub struct ConnectionLimits {
    pub max_clients: usize,
    pub max_frame_bytes: usize,
    pub read_timeout: Duration,
    pub write_timeout: Duration,
    pub drain_timeout: Duration,
}

pub struct ConnectionContext {
    pub peer_pid: u32,
    pub peer_uid: u32,
    pub cancellation: CancellationToken,
}
```

- [ ] **Step 4: Migrate event/control sockets and add readiness**

Bind v2 and new v3 listeners before starting producers. Add the `sd-notify` crate with `default-features = false`; call `sd_notify::notify(false, &[NotifyState::Ready])` only after stores and listeners are ready. Emit `STOPPING=1` before drain. Preserve current v2 socket paths and documents.

- [ ] **Step 5: Run daemon verification**

```bash
cargo fmt --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --test socket_supervisor
cargo test --locked
```

Expected: PASS, including existing v2 daemon/socket tests.

- [ ] **Step 6: Commit supervisor and readiness**

```bash
git add Cargo.toml Cargo.lock src/sessiond src/bin/sleepy-sessiond.rs tests/socket_supervisor.rs
git commit -m "feat: supervise desktop sockets and signal readiness"
```

### Task 4: Implement the Hyprland state and action adapter

**Repository:** `sleepy-session`

**Files:**
- Create: `src/compositor/mod.rs`
- Create: `src/compositor/hyprland.rs`
- Create: `src/compositor/protocol.rs`
- Create: `tests/hyprland_adapter.rs`
- Create: `tests/fixtures/hyprland/monitors.json`
- Create: `tests/fixtures/hyprland/workspaces.json`
- Create: `tests/fixtures/hyprland/clients.json`
- Modify: `src/lib.rs`
- Modify: `src/sessiond/sources.rs`
- Modify: `src/sessiond/mutation.rs`

**Interfaces:**
- Consumes: `HYPRLAND_INSTANCE_SIGNATURE`, Hyprland command/event Unix sockets, SDK `HyprlandSnapshot` and `HyprlandCommand`.
- Produces: `HyprlandAdapter::snapshot()`, `HyprlandAdapter::run_events()`, and `HyprlandAdapter::execute()` with confirmed readback.

- [ ] **Step 1: Write failing parser and reconciliation tests**

Parse monitor/workspace/client fixtures, then replay `workspace`, `focusedmon`, `openwindow`, `closewindow`, `movewindow`, `fullscreen`, and `monitoradded/removed` events. Assert stable IDs, focused monitor/window, special workspaces, output hotplug, and that malformed one-line events degrade only compositor state.

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `cargo test --locked --test hyprland_adapter`

Expected: FAIL with missing compositor module.

- [ ] **Step 3: Implement socket discovery and strict parsing**

Resolve the instance directory from the signature without traversal, open `.socket.sock` and `.socket2.sock` directly, cap responses/events, and never invoke a shell. Reconcile from full JSON on connect, on event lag, and at a bounded 30 s fallback interval.

```rust
#[async_trait]
pub trait CompositorAdapter: Send + Sync {
    async fn snapshot(&self) -> Result<HyprlandSnapshot, CompositorError>;
    async fn execute(&self, command: HyprlandCommand)
        -> Result<HyprlandSnapshot, CompositorError>;
    async fn run_events(&self, sender: mpsc::Sender<HyprlandEvent>)
        -> Result<(), CompositorError>;
}
```

- [ ] **Step 4: Implement typed actions with readback**

Map only SDK commands to fixed Hyprland dispatchers: focus/move/close window, focus/move workspace, fullscreen, floating, pin, group, and exit. Encode user-independent numeric/address arguments, apply a 2 s deadline, then reread state until the expected condition or timeout. Publish confirmation only after readback.

- [ ] **Step 5: Replace Niri runtime production with Hyprland production**

Add a typed Hyprland availability record to v3 `DesktopSnapshot.compositor`
while leaving the v2 `RuntimeCapabilityId::Niri` behavior unchanged for
compatibility. Remove Niri from new mutation routing and ensure absent Hyprland
changes only the v3 compositor capability.

- [ ] **Step 6: Verify and commit**

```bash
cargo fmt --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --test hyprland_adapter
cargo test --locked
git add src/compositor src/lib.rs src/sessiond tests/hyprland_adapter.rs tests/fixtures/hyprland
git commit -m "feat: add confirmed Hyprland session adapter"
```

### Task 5: Expand daemon desktop services by domain

**Repository:** `sleepy-session`

**Files:**
- Create: `src/desktop/mod.rs`
- Create: `src/desktop/audio.rs`
- Create: `src/desktop/network.rs`
- Create: `src/desktop/bluetooth.rs`
- Create: `src/desktop/resources.rs`
- Create: `src/desktop/media.rs`
- Create: `src/desktop/tray.rs`
- Create: `src/desktop/clipboard.rs`
- Create: `src/desktop/utilities.rs`
- Create: `src/desktop/secret_agent.rs`
- Create: `tests/desktop_services.rs`
- Modify: `src/system/*.rs`
- Modify: `src/sessiond/sources.rs`
- Modify: `src/sessiond/mutation.rs`

**Interfaces:**
- Consumes: SDK desktop v3 domain snapshots/commands, NetworkManager, BlueZ, UPower, power-profiles-daemon, PipeWire/WirePlumber, MPRIS, StatusNotifierItem/DBusMenu, logind, `/proc`, `/sys`, portals.
- Produces: independent producer actors, typed mutations, one-shot secret requests, and a complete v3 snapshot within two seconds.

- [ ] **Step 1: Write a table-driven failing service contract test**

For every producer, inject a fake D-Bus/runner/event source and assert `available`, `unavailable`, `permissionDenied`, `timeout`, `parse`, and `error` terminal states. Add mutation/readback cases for audio nodes and streams, Wi-Fi scan/connect/disconnect, Bluetooth pair/connect, power/night light, MPRIS, tray menus, clipboard, idle inhibit, recording, screenshot/color pick, and logind actions.

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `cargo test --locked --test desktop_services`

Expected: FAIL with missing `desktop` services.

- [ ] **Step 3: Implement event-first producers**

Use native D-Bus/IPC subscriptions where available and bounded reconciliation otherwise. Each actor owns its connection, publishes through one registry keyed by exhaustive SDK domain IDs, and reaches a terminal state within two seconds. Keep file and network I/O off Tokio core workers.

```rust
#[async_trait]
pub trait DesktopProducer: Send + Sync {
    fn domain(&self) -> DesktopDomainId;
    async fn initial(&self) -> DesktopDomainState;
    async fn run(
        &self,
        sender: mpsc::Sender<DesktopDomainUpdate>,
        cancellation: CancellationToken,
    ) -> Result<(), ProducerError>;
}
```

- [ ] **Step 4: Implement fixed mutations and secret isolation**

Use typed D-Bus calls or fixed argv vectors only. Network secrets use `secret.sock`: one peer-verified client, one request, 64 KiB maximum, 30 s deadline, no replay, no event serialization, and buffer zeroization after NetworkManager accepts or rejects the secret. Use interactive polkit/logind results for power actions and remove broad wheel bypass behavior.

- [ ] **Step 5: Add the v3 event and request endpoints**

Serve `$XDG_RUNTIME_DIR/sleepy/desktop.sock` and `desktop-control.sock` through `SocketSupervisor`. A new client receives one `FullSnapshot`; incremental events have monotonic generation and typed causes. Deduplicate request IDs durably and require exact expected generation plus confirmed readback.

- [ ] **Step 6: Verify and commit domain services**

```bash
cargo fmt --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --test desktop_services
cargo test --locked
git add src/desktop src/system src/sessiond tests/desktop_services.rs
git commit -m "feat: provide Sleepy desktop system services"
```

### Task 6: Import and rename the visual shell

**Repository:** `sleepy-desktop`

**Files:**
- Replace: `src/` with the approved imported visual source plus Sleepy adapters
- Create: `src/Sleepy/` native QML plugin namespace
- Create: `src/services/DesktopClient.qml`
- Create: `src/services/DesktopModel.qml`
- Create: `src/services/CommandClient.qml`
- Create: `tests/runtime-names.sh`
- Create: `tests/service-boundary.sh`
- Modify: `CMakeLists.txt`
- Modify: `flake.nix`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: Task 1 importer and Task 2 v3 schemas/fixtures.
- Produces: `sleepy-shell`, `Sleepy.*` QML namespace, Sleepy configuration paths, reconnecting desktop client, and no Caelestia runtime identity.

- [ ] **Step 1: Run the guarded import**

Clone the public shell into a temporary checkout, detach at the verified commit, verify the tag object with `gh api`, and run:

```bash
scripts/import-upstream.sh --source "$verified_shell_checkout"
```

Expected: approved source paths are imported; no dots repository content appears.

- [ ] **Step 2: Write failing naming and service-boundary tests**

`tests/runtime-names.sh` permits `Caelestia` only in `NOTICE`, `LICENSE`, `UPSTREAM.json`, modification notices, and source provenance comments. It rejects Caelestia QML URIs, executable names, config paths, IPC targets, logging categories, and visible strings in installed output.

`tests/service-boundary.sh` rejects `Process`, `Quickshell.execDetached`, and command tokens `nmcli|bluetoothctl|wpctl|playerctl|brightnessctl|powerprofilesctl|upower|hyprctl|loginctl|systemctl` under QML service code, except the test fixtures and approved compositor-connected helper bindings.

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
bash tests/runtime-names.sh
bash tests/service-boundary.sh
```

Expected: FAIL on imported Caelestia namespaces/services.

- [ ] **Step 4: Rename the product boundary and retain modification notices**

Rename C++ namespace/QML URI `Caelestia` to `Sleepy`, config path helpers to `$XDG_CONFIG_HOME/sleepy`, state/cache helpers to their Sleepy XDG paths, executable to `sleepy-shell`, and logging categories to `sleepy.*`. Add SPDX and modification-date notices to changed upstream files. Keep legal credits accessible in the About surface.

- [ ] **Step 5: Replace upstream services with the v3 client model**

Implement one bounded reconnecting client for `desktop.sock` and one serialized request client for `desktop-control.sock`. Use exponential retry 250 ms to 10 s, stop retry after success, reconnect after disconnect, reject out-of-order generations, and clear at most 64 observed request IDs on daemon generation change. Expose typed QML models; do not retain upstream process/file service implementations.

```qml
DesktopProtocol {
    eventSocketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sleepy/desktop.sock"
    controlSocketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sleepy/desktop-control.sock"
    minimumRetryMs: 250
    maximumRetryMs: 10000
    maximumObservedRequests: 64
}
```

- [ ] **Step 6: Build the renamed native plugin and packages**

Adapt the upstream CMake/Nix build to compile only audited render helpers, link the pinned Quickshell/m3shapes/Qt packages, and produce `sleepy-shell` plus `sleepy-settings-preview`. Remove any dependency on Caelestia CLI.

- [ ] **Step 7: Verify and commit the fork boundary**

```bash
bash tests/upstream-provenance.sh
bash tests/runtime-names.sh
bash tests/service-boundary.sh
bash tests/run.sh
bash scripts/validate-qml.sh
git add .
git commit -m "feat: fork and rename the Sleepy visual shell"
```

### Task 7: Port core surfaces to Sleepy models

**Repository:** `sleepy-desktop`

**Files:**
- Modify: `src/modules/bar/**`
- Modify: `src/modules/launcher/**`
- Modify: `src/modules/dashboard/**`
- Modify: `src/modules/sidebar/**`
- Modify: `src/modules/notifications/**`
- Modify: `src/modules/osd/**`
- Modify: `src/modules/nexus/**`
- Create: `tests/qml/tst_desktop_models.qml`
- Create: `tests/qml/tst_core_surfaces.qml`

**Interfaces:**
- Consumes: `DesktopModel` properties and `CommandClient.send(command)`.
- Produces: core surfaces with upstream-equivalent layout/animation and all state/actions routed through Sleepy.

- [ ] **Step 1: Write failing QML model tests**

Feed a deterministic full-snapshot fixture, then incremental network, audio, workspace, media, notification, and theme events. Assert stable list identities, focused output selection, reconnect reset, lag recovery, and disabled controls for unavailable capabilities.

- [ ] **Step 2: Run model tests to verify they fail**

Run: `bash tests/run.sh`

Expected: FAIL because imported surfaces still reference removed upstream services.

- [ ] **Step 3: Port bar, workspaces, tray and OSD**

Bind workspaces/windows/monitors, tray models, clock, battery, Bluetooth, network, audio, and OSD to `DesktopModel`. Send only SDK-shaped command objects through `CommandClient`. Preserve per-monitor focus and fullscreen suppression behavior.

- [ ] **Step 4: Port launcher, dashboard, sidebar and notifications**

Bind launcher modes, app search, calculator, wallpapers/schemes, media/calendar/weather/resources, history/DND/actions, and settings pages to daemon models. Keep only presentation filter/sort state in QML; filesystem, network, persistence, and process work stay in the daemon.

- [ ] **Step 5: Run QML/static/package checks**

```bash
bash tests/runtime-names.sh
bash tests/service-boundary.sh
bash tests/run.sh
bash scripts/validate-qml.sh
```

Expected: PASS in the Nix/QML runner environment.

- [ ] **Step 6: Commit core surfaces**

```bash
git add src tests
git commit -m "feat: connect Sleepy core desktop surfaces"
```

### Task 8: Implement the fail-secure Sleepy locker

**Repositories:** `sleepy-desktop`, root `sleepy`

**Files:**
- Create: `sleepy-desktop/locker/CMakeLists.txt`
- Create: `sleepy-desktop/locker/main.cpp`
- Create: `sleepy-desktop/locker/secureprompt.{hpp,cpp}`
- Create: `sleepy-desktop/locker/qml/LockRoot.qml`
- Create: `sleepy-desktop/tests/locker-boundary.sh`
- Create: `sleepy-desktop/tests/locker_native.cpp`
- Modify: `sleepy-desktop/flake.nix`
- Create: `sleepy/modules/nixos/session/pam.nix`
- Create: `sleepy/modules/home/locker/default.nix`

**Interfaces:**
- Consumes: private peer-verified lock request, PAM service `sleepy-locker`, `ext-session-lock-v1`.
- Produces: `sleepy-locker`, `sleepy-locker.service`, no public unlock command, fail-safe return to ReGreet.

- [ ] **Step 1: Write failing native and source-boundary tests**

Assert that correct PAM fake unlocks, incorrect/empty input does not, native buffer zeroizes on every exit path, QML sees only length/status, no `unlock` IPC/global shortcut exists, and every connected monitor gets a lock surface before secure acknowledgement.

- [ ] **Step 2: Run locker tests to verify they fail**

Run:

```bash
bash tests/locker-boundary.sh
cmake --build build --target sleepy-locker-tests
ctest --test-dir build -R sleepy-locker
```

Expected: FAIL because locker targets do not exist.

- [ ] **Step 3: Implement native secure prompt and PAM conversation**

Handle native Qt key/input-method events, immediately copy transient text to locked mutable memory, expose only length/status to QML, call PAM through the root-defined service, and zeroize on submit/cancel/failure/destruction/shutdown. Do not serialize credentials or retain a persistent `QString`.

```cpp
class SecurePrompt final : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(int inputLength READ inputLength NOTIFY inputLengthChanged)
    Q_PROPERTY(AuthState authState READ authState NOTIFY authStateChanged)
public:
    bool authenticate();
    void clearSecret() noexcept;
protected:
    void keyPressEvent(QKeyEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
private:
    LockedSecretBuffer secret_;
};
```

- [ ] **Step 4: Implement Wayland lock lifecycle**

Acquire the session lock, create a fallback-capable surface per output, acknowledge secure only after all current outputs are covered, handle hotplug, and allow unlock-and-destroy only from the successful PAM callback. Shell or daemon failure must not unlock.

- [ ] **Step 5: Add systemd/PAM fail-safe integration**

Define `security.pam.services.sleepy-locker`. Start a persistent locker with the UWSM graphical session. `OnFailure=` invokes a fixed fail-safe unit that terminates that graphical session to ReGreet. The daemon sends only `lock`; suspend waits for locked acknowledgement.

- [ ] **Step 6: Verify and commit both repositories**

Run locker native/QML tests, root module evaluation in Nix, and source-boundary tests. Commit `sleepy-desktop` as `feat: add fail-secure Sleepy locker`; commit root as `feat: integrate Sleepy locker lifecycle`.

### Task 9: Author the Sleepy Hyprland configuration and UWSM session

**Repository:** root `sleepy`

**Files:**
- Delete: `modules/home/niri/**`
- Create: `modules/home/hyprland/default.nix`
- Create: `modules/home/hyprland/settings.nix`
- Create: `modules/home/hyprland/binds.nix`
- Create: `modules/home/hyprland/rules.nix`
- Create: `modules/home/hyprland/appearance.nix`
- Modify: `modules/home/default.nix`
- Modify: `modules/home/session/default.nix`
- Modify: `modules/home/quickshell/default.nix`
- Modify: `modules/nixos/session/default.nix`
- Delete: `modules/nixos/base/niri-version.nix`
- Modify: `modules/nixos/base/default.nix`
- Create: `checks/hyprland-config.nix`
- Rewrite: `checks/session-contract.nix`

**Interfaces:**
- Consumes: pinned Hyprland/UWSM/Home Manager modules and Sleepy package outputs.
- Produces: ReGreet-selectable UWSM Hyprland session, authored Sleepy configuration, portal routing, and correctly ordered user units.

- [ ] **Step 1: Write failing root contracts**

Assert Hyprland and UWSM enabled, ReGreet enabled, autologin absent, XWayland enabled, portal preference `hyprland;gtk`, `sleepy-session.service` is `Type=notify`, shell uses `Wants/After` without `Requires`, locker is `PartOf` the UWSM target, and no active Niri package/unit/config remains.

- [ ] **Step 2: Run static contracts to verify they fail**

Run the modified shell contract scripts directly.

Expected: FAIL on current Niri configuration.

- [ ] **Step 3: Enable Hyprland/UWSM and author config**

Use `programs.hyprland.enable = true`, XWayland, `programs.uwsm.enable = true`, and Home Manager `wayland.windowManager.hyprland`. Author monitor defaults, keyboard/mouse/touchpad, animations, rounded decoration, blur, shadows, gaps, groups, special workspaces, rules, environment, and Sleepy IPC binds without copying dots source. Map terminal to Ghostty and browser to Firefox.

```nix
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };
  programs.uwsm.enable = true;
  services.greetd.enable = true;
  services.displayManager.regreet.enable = true;
}
```

- [ ] **Step 4: Configure portals and graphical user units**

Prefer xdg-desktop-portal-hyprland for screencast/screenshot and GTK for file chooser. Bind shell, daemon, locker, polkit agent, keyring, and clipboard helper to the UWSM graphical target. Remove Niri binding activation and online reconciliation; preserve its files as untouched legacy data.

- [ ] **Step 5: Validate generated configuration and root graph**

Inside a Nix-enabled environment run:

```bash
nix build .#checks.x86_64-linux.hyprland-config --no-link -L
nix build .#checks.x86_64-linux.session-contract --no-link -L
nix flake check --no-write-lock-file -L
```

Expected: PASS and checkout remains unchanged.

- [ ] **Step 6: Commit root session replacement**

```bash
git add modules checks
git commit -m "feat: replace Niri with the Sleepy Hyprland session"
```

### Task 10: Finish remaining visual and utility parity

**Repositories:** `sleepy-session`, `sleepy-desktop`

**Files:**
- Modify: `sleepy-session/src/desktop/**`
- Modify: `sleepy-desktop/src/modules/utilities/**`
- Modify: `sleepy-desktop/src/modules/windowinfo/**`
- Modify: `sleepy-desktop/src/modules/background/**`
- Modify: `sleepy-desktop/src/modules/session/**`
- Create: `sleepy-desktop/tests/parity-manifest.json`
- Create: `sleepy-desktop/tests/qml/tst_parity.qml`
- Create: `sleepy-desktop/tests/parity.sh`

**Interfaces:**
- Consumes: exhaustive upstream inventory and v3 domain services.
- Produces: every imported upstream surface classified and every retained behavior mapped to a passing test or approved deviation.

- [ ] **Step 1: Write the failing parity manifest test**

Require an entry for every imported upstream QML/C++ service/module with `disposition`, `sleepyOwner`, `protocol`, `degradedState`, and `tests`. Require objective cases for bar/taskbar, all launcher modes, dashboard/sidebar, OSD, lock/session, network/Bluetooth/audio, media/lyrics, utilities, compositor/window info, appearance, scaling, two monitors, and hotplug.

- [ ] **Step 2: Run parity test to verify it fails**

Run: `bash tests/parity.sh`

Expected: FAIL on missing inventory entries and cases.

- [ ] **Step 3: Implement retained utility behavior**

Complete idle inhibit lease, recording lifecycle, screenshot/area selection, color picker, game mode, wallpaper/theme, window details/preview, special workspaces, reduced motion, opaque mode, and multi-monitor behavior. Every privileged or persistent action crosses the daemon boundary; compositor-connected helpers remain narrow and gesture-gated.

- [ ] **Step 4: Capture deterministic visual references and compare**

Run exact upstream v2.4.0 and Sleepy with fixed 1280x800 and two-monitor fixtures, fixed wallpaper/fonts/locale/clock, software RHI, and settled animations. Store only licensed/generated fixture captures. Assert surface presence, anchors, clipping, overflow, semantic colors, and documented pixel tolerance.

- [ ] **Step 5: Verify and commit parity**

Run full Rust, QML, CMake, provenance, boundary, and parity suites. Commit session as `feat: complete Sleepy desktop utility services`; commit desktop as `feat: complete Sleepy visual parity`.

### Task 11: Pin compatible components and add reversible VM acceptance

**Repository:** root `sleepy`

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `components/current.json` or the active component manifest
- Modify: `overlays/default.nix`
- Modify: `checks/default.nix`
- Create: `checks/hyprland-production-vm.nix`
- Create: `docs/runbooks/sleepy-vm-hyprland.md`
- Create: `docs/acceptance/hyprland-sleepy-desktop.md`
- Create: `scripts/vm/capture-baseline.sh`
- Create: `scripts/vm/verify-restore.sh`
- Create: `scripts/vm/collect-evidence.sh`

**Interfaces:**
- Consumes: reviewed public component commits from Tasks 2–10 and libvirt domain `Sleepy`.
- Produces: locked root graph, automated NixOS VM gate, verified rollback bundle, real virt-manager guest evidence.

- [ ] **Step 1: Write failing component and VM contracts**

Assert exact SDK/session/desktop pins, matching lock nodes, no dirty checkout after evaluation, ReGreet → UWSM → Hyprland → ready daemon → shell ordering, full v3 snapshot, absence of Niri, expected shell surfaces, and prior-generation boot preservation.

- [ ] **Step 2: Pin compatible reviewed revisions**

Push component branches with `GH_TOKEN="$(gh auth token --user f1nallylost)"`, record their exact commits, update literal inputs and the current manifest together, and update `flake.lock` only in the Nix-enabled VM. Do not switch the global `gh` account.

- [ ] **Step 3: Build the complete root graph before touching the existing VM**

Run in Nix:

```bash
nix flake check --no-write-lock-file -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel --no-link -L
nix build .#checks.x86_64-linux.hyprland-production-vm --no-link -L
git diff --exit-code
```

Expected: PASS and clean checkout.

- [ ] **Step 4: Capture and drill the existing VM rollback bundle**

With `Sleepy` shut down, create a mode-0700 run directory and capture inactive XML, NVRAM, disk metadata/backing chain, checksums, and an offline qcow2 copy or verified supported snapshot. Restore into a temporary verification domain, boot it, confirm the recorded generation and ReGreet, then remove only the temporary verification domain. Keep baseline artifacts until acceptance completes.

- [ ] **Step 5: Apply and test in the real `Sleepy` virt-manager VM**

Build/switch the candidate inside the guest, reboot, log in through ReGreet, and verify Hyprland IPC, full v3 snapshot, shell/locker/daemon units, zero failed units, no Niri process, launcher, workspaces, notification, theme/wallpaper, network/audio, degraded absent hardware, daemon/shell restart recovery, lock crash cases, suspend/resume, logout to ReGreet, portal file chooser, and screencast.

- [ ] **Step 6: Visually inspect redacted framebuffer evidence**

Capture ReGreet, unlocked desktop, launcher/dashboard/sidebar, lock screen, and post-recovery desktop through SPICE/framebuffer. Store mode-0600 artifacts, redact SSIDs/notification text/paths/device names, inspect each image, hash the accepted evidence, and record deletion date.

- [ ] **Step 7: Test downgrade and return to candidate**

Boot the prior Niri generation, verify legacy state hashes and essential login, then boot the Hyprland generation and repeat readiness checks. If any failure trigger occurs, execute the tested rollback runbook before further changes.

- [ ] **Step 8: Commit acceptance evidence and root integration**

Commit only the redacted report, hashes, commands, component revisions, and non-sensitive screenshots approved for retention. Never commit raw journals or user data.

```bash
git add flake.nix flake.lock components overlays checks modules docs scripts
git commit -m "feat: integrate and validate the Hyprland Sleepy desktop"
```

### Task 12: Final verification and independent review

**Repositories:** all four feature branches

**Files:**
- Modify only files required by verified review findings.

**Interfaces:**
- Consumes: all commits and acceptance evidence.
- Produces: clean branches ready for user-approved PR creation; no merge is implied.

- [ ] **Step 1: Run complete verification from clean worktrees**

Run SDK/session fmt, Clippy `-D warnings`, locked debug/release tests; desktop QML/CMake/static/RHI/package/parity tests; root locked flake/build/VM checks; and `git diff --exit-code` after every Nix command.

- [ ] **Step 2: Dispatch independent review**

Give the reviewer exact base/head SHAs and the spec/plan. Require review of GPL/provenance, secret paths, locker fail-secure behavior, direct-command escapes, protocol limits, UWSM lifecycle, state preservation, and real VM evidence.

- [ ] **Step 3: Verify and resolve every Critical/Important finding**

Reproduce each finding, add a failing regression test, implement the smallest fix, rerun the focused and full suites, and commit per repository. Push back only with test/source evidence.

- [ ] **Step 4: Present completion and PR options**

Report branch names, commits, test commands/results, VM state, rollback artifact location/retention, visual evidence, known unavailable VM hardware, and review verdict. Use `gh` with the per-command `f1nallylost` token only after the user authorizes PR creation for the completed branches.
