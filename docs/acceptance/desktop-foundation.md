# Sleepy desktop foundation acceptance

## Desktop Milestone 1 integration candidate

**BLOCKED pending live Wayland/VM boot and visual acceptance.** The distribution
integration consumes only these reviewed component revisions:

| Component | Reviewed revision |
|---|---|
| `sleepy-sdk` | `2edbe8310eee69c40e4f75924da67a57942bd1c3` |
| `sleepy-session` | `1e8863839b5c4310bce251b7e10ed15926039930` |
| `sleepy-artwork` | `0dd59cc9d8a77700f7a415997e3dcde396f55e99` |
| `sleepy-desktop` | `a88fba369d3926981c46b837c88483553559a60a` |

The generated `flake.lock` has SHA-256
`64f819a051bdeb0be8e44b146316d8317b4a8e10ca700148ba2e93ff7b770bca`,
contains the four component inputs above, and passes the executable component
lock contract. A clean-copy Docker run using `nixos/nix:latest` and a persistent
cache executed:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake check --print-build-logs
```

It exited 0 with final output `all checks passed!` after building the SDK and
session tests, standalone Home Manager activation, update-safety and component
contracts, Quickshell checks, and the NixOS system closure. This records the
full Nix evaluation/build gate as PASS. Live Wayland/VM boot, activation,
user-state preservation, and visual smoke remain unverified and are not
claimed here. Record final live acceptance only after the remaining VM steps
below pass.

Regenerate the lock only from the flake inputs and validate it; never add lock
nodes or `narHash` values by hand:

```bash
nix flake lock
bash checks/component-lock.sh components/desktop-m1.json flake.lock
git diff -- flake.lock
sha256sum flake.lock
```

Then run the complete distribution gate from that exact clean commit:

```bash
nix flake check -L --no-write-lock-file
nix build .#sleepy-contract .#sleepy-session \
  .#sleepy-session-user-unit .#sleepy-artwork \
  .#sleepy-shell .#sleepy-settings-preview --no-link -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel \
  --no-link --no-write-lock-file -L
nix build '.#homeConfigurations."lazy@sleepy-vm".activationPackage' \
  --no-link --no-write-lock-file -L
```

VM acceptance must preserve an existing
`$XDG_CONFIG_HOME/sleepy/settings.json` and
`$XDG_STATE_HOME/sleepy/presets.json`, activate through `dry-activate` then
`test`, and confirm `sleepy-session.service` is `active/exited`, belongs to
`graphical-session.target`, and executes the packaged `sleepyctl`. Validate
`sleepyctl settings show` with the packaged `sleepy-contract`, then smoke-test
the external rail, drawer, artwork, and settings preview before switching.

The in-tree `packages/sleepy-shell` and `packages/sleepy-branding` remain as a
reviewable fallback. Delete them only after the generated lock, full flake
check, external package builds, standalone Home Manager activation, and VM
visual/state acceptance all pass at one recorded candidate commit.

## Result

**PASS — 2026-08-23.** Commit
`d9036c1c957a685d789449a42e334a6183b72eac` was built from a clean public
archive, test-activated, interactively accepted, and permanently switched in
the localhost-only libvirt user-session VM `Sleepy`.

The accepted runtime and permanent system profile both resolve to:

```text
/nix/store/lfyl6fraa4nb404vcdrb8inxk2f13hpx-nixos-system-sleepy-vm-26.11.20260822.2c423e0
```

System generation 5 is current. Generations 1 through 4 remain present; no
generation deletion or garbage collection occurred.

## Build, deployment, and state evidence

| Check | Observed evidence | Result |
|---|---|---|
| Clean public source | Exact `git archive` SHA-256 `c5c2f90227d63b81184d53842dd88ee94a1d79c1583cbb0f187ae72fa692e186`; excluded private/ignored paths; source-clean passed before and after deployment | PASS |
| Full verification | Full `nix flake check -L --no-write-lock-file` ended `all checks passed!`; explicit toplevel build produced `lfyl6…`; only the known non-fatal `homeManagerModules` warning appeared | PASS |
| Reversible activation | Before the permanent switch, authenticated `nixos-rebuild test` activated `lfyl6…` without changing the boot profile or the four-generation set; SSH remained reconnectable | PASS |
| Permanent switch | Authenticated `nixos-rebuild switch` returned `Done`; runtime and system profile both became `lfyl6…`; generation 5 was added and predecessors remained | PASS |
| Ordered final-candidate gate | After review, the exact already-deployed `/etc/sleepy` candidate ran authenticated `dry-activate` and then `test` in that order under `&&`; both returned `Done` for `lfyl6…`, with runtime, boot profile, five-generation set, user-state hashes, links, SSH, and graphical session unchanged | PASS |
| Deployed tree | `/etc/sleepy` is root-owned, content-identical to the verified staged archive, and passes source-clean; earlier public trees remain under two unique backup paths | PASS |
| User-owned state | Authorized-keys metadata/hash, user Nix profile hash, migration backup, and managed Niri links remained unchanged; no credential contents were recorded | PASS |
| Test-file cleanup | Settings and sentinel origins were both recorded `created`; their hashes matched after switching, then only those two files were removed and verified absent | PASS |

The user Nix profile hash remained
`712b11070ffada765902c93e8c5a36f9b71b723c94bfb072f048479ab343f910`.
The adopted Niri backup remained at its recorded path with SHA-256
`993aa205ed47eada18b0ed85a8d4c7b31480c56c9d182840121943dd286ad080`.

The ordered final-candidate gate above was performed after the permanent
switch to close a review evidence gap; it was not a pre-switch dry activation.
An initial invocation that omitted the leading slash from `etc/sleepy` failed
before activation, so its `&&` right-hand side did not run. The corrected exact
command used `/etc/sleepy`: dry activation printed `would activate the
configuration` and `Done` for `lfyl6…`; only then did the test activation run
and print its own `Done` for the same toplevel.

## Interactive desktop evidence

| Acceptance item | Observed evidence | Result |
|---|---|---|
| ReGreet to Niri | The user authenticated through ReGreet. The session was `lazy` on seat0 with `graphical-session.target`, Niri, Quickshell, and the graphical polkit agent active | PASS |
| Session environment | The user manager exported `WAYLAND_DISPLAY=wayland-1`, `DISPLAY=:0`, `XDG_CURRENT_DESKTOP=niri`, `XDG_SESSION_TYPE=wayland`, and a live `NIRI_SOCKET` | PASS |
| Workspace | Niri reported active workspaces. Moving a reversible test window to workspace 2 changed both Niri state and the panel indicators; the test window was removed | PASS |
| Lunar Minimal panel | Trustworthy guest-framebuffer inspection showed the 52 px dark left panel, Lunar moon mark, workspace column, centered network tray item, clock, and bottom user marker | PASS |
| `Mod+T` | Direct guest input created a focused Niri-managed Ghostty window and a Fish child | PASS |
| `Mod+Return` | Direct guest input created a second Ghostty surface | PASS |
| Ghostty VM wrapper | Profile Ghostty resolved to `ghostty-sleepy-vm-1.3.1`; its Fish child inherited exactly `LIBGL_ALWAYS_SOFTWARE=1`. The variable was not exported session-wide | PASS |
| `Mod+D` | Direct guest input started Fuzzel and Niri reported its exclusive `launcher` overlay; the visible launcher contained Firefox and Ghostty | PASS |
| Firefox portal | Firefox opened as a Niri window. Guest `Ctrl+O` produced a focused `Open File - Mozilla Firefox` window from the GNOME portal while portal, GNOME, and GTK portal services were active | PASS |
| X11 compatibility | A lock-pinned `xmessage` client appeared as Niri window `Xmessage`; the live `xwayland-satellite` process was a direct child of Niri, with no separate Satellite service | PASS |
| Keyboard layouts | Guest `Alt+Shift` changed Niri's active layout from English (US) to Russian; a second toggle restored English (US) | PASS |
| Host-key distinction | Binding tests used direct libvirt guest key events. They therefore prove guest Niri behavior independently of host Super-key interception | PASS |

Visual evidence was taken only from the guest framebuffer. A Firefox portal
capture that displayed unrelated home-directory names was discarded and is not
part of the retained evidence.

## Failure and lifecycle evidence

| Acceptance item | Observed evidence | Result |
|---|---|---|
| Quickshell restart limit | The original run reached the declared three-failure limit. A fresh post-review run began with healthy PID 25572, then exactly three controlled SIGSEGV failures used PIDs 25572, 25648, and 25720. The unit reached `ActiveState=failed`, `SubState=failed`, `Result=start-limit-hit`, `NRestarts=3`, and `MainPID=0` | PASS |
| Fallback bindings | In the original failed-panel run, `Mod+T`, `Mod+Return`, `Mod+Left`, `Mod+Right`, and `Mod+D` remained operational. In the post-review failed-panel run, direct guest `Mod+Shift+E` displayed Niri's exit confirmation; direct guest Escape cancelled it, the session survived, and Quickshell remained at its start limit until the explicit reset | PASS |
| Quickshell restoration | After the post-review prompt cancellation, `reset-failed` plus managed `start` restored PID 25811 as `active/running`, `Result=success`, `NRestarts=0`; trustworthy guest-framebuffer inspection confirmed the top-layer panel was visible again | PASS |
| Invalid candidate | An isolated NixOS `extendModules` assertion failed with exit 1 before activation. Runtime, boot profile, exact generation-set hash, SSH, Niri, and Quickshell were unchanged; the previous generation activation entrypoint remained available | PASS |
| Niri logout lifecycle | `Mod+Shift+E` displayed Niri's exit confirmation; guest Enter confirmed it. Niri, `graphical-session.target`, Quickshell, and the polkit agent became inactive while greetd and SSH remained active | PASS |
| ReGreet return | greetd opened a new greeter PAM session with Cage and ReGreet. The user logged back in, producing a fresh Niri socket and healthy graphical services before the permanent switch | PASS |

## Final health

After the permanent switch, SSH reconnected; `sshd.service`,
`graphical-session.target`, Niri, Quickshell, and the graphical polkit agent were
active. Quickshell reported `active/running`, `Result=success`, and
`NRestarts=0`. The post-review ordered gate left the same runtime, permanent
profile, five generations, managed links, and recorded user-state hashes in
place. The finalization and review terminals were closed after their successful
results, and the graphical session remained healthy.
