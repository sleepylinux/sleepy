# Sleepy desktop foundation acceptance

## Desktop Milestone 2 integration candidate

**PASS — permanently deployed and reboot-verified in the `Sleepy` VM.** The
distribution integration consumes only these reviewed component revisions:

| Component | Reviewed revision |
|---|---|
| `sleepy-sdk` | `5dc792faea9d743fabbb576ae1b25ed7e1f729f9` |
| `sleepy-session` | `b88f5b993ae449acf176d8fc6f0d6542776d06bd` |
| `sleepy-artwork` | `108487617077254edb4e3a3b21047f5621eef151` |
| `sleepy-desktop` | `0b612df154e0606ced56020a56a54fa1f42dd3db` |

The generated `flake.lock` has SHA-256
`37077bba388939aa3b848cd53031f92c5ad07d5b13ac7314e4462985603bab82`,
contains the four component inputs above, and passes the executable component
lock contract. The final clean-copy gate uses `nixos/nix:2.35.2` with a
persistent cache and `/dev/kvm`; on 2026-08-24 it executed:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake check -L --no-write-lock-file
```

The clean-copy run exited 0 with final output `all checks passed!`; its
`sleepy-m1-to-m2-update-safety` QEMU test completed in 17.73 seconds. Explicit
builds produced these candidate outputs:

| Output | Store path |
|---|---|
| `sleepy-contract` | `/nix/store/1hma6bvlaj9i4sf4dj25kp1hbkxd1mhv-sleepy-sdk-0.1.0` |
| `sleepy-session` | `/nix/store/s05bf253170i8ahz2w2wa5dy9lncnbwh-sleepy-session-0.1.0` |
| `sleepy-session-user-unit` | `/nix/store/9nlxhfr441yz5i43gf65qfqzab4s6sz5-sleepy-session.service` |
| `sleepy-artwork` | `/nix/store/nh341wq9kf7bbx6nn4i2bqvcy6qyh6ar-sleepy-artwork-0.1.0` |
| `sleepy-shell` | `/nix/store/xkplqqfncs3wnqvdb5zbr3vmc97cap9p-sleepy-shell-0.2.0` |
| `sleepy-settings-preview` | `/nix/store/90q1fczz1r81vjimg3bp24n8r55znnsx-sleepy-settings-preview-0.2.0` |
| NixOS toplevel | `/nix/store/28ci2cfi4inrg4jvr9vxqgw91vwq8x68-nixos-system-sleepy-vm-26.11.20260822.2c423e0` |
| Standalone Home Manager activation | `/nix/store/w30qvcz43n3300n8amk7baj7hlh4acbb-home-manager-generation` |
| Artwork assets check | `/nix/store/2a4vdax6s2467mfnyhzhkmbs5zanm04x-sleepy-artwork-contracts` |
| Desktop QML check | `/nix/store/6pmc2c02jj0931pn7rvkyfcw01q7ykb3-sleepy-desktop-qml-contracts` |
| Desktop package check | `/nix/store/zbv9c9ds00a1wd5fs8cwlayqh8qq8vg0-sleepy-desktop-package-contracts` |
| Desktop preview check | `/nix/store/3z7lv9jnxrdgickzlxavrs1ah3kh8dhl-sleepy-desktop-preview-contracts` |

The accepted root source commit is
`1aa712237c60494b2690eccc75aaa37a87225a03`. Target-VM generation,
state-preservation, live input, and visual acceptance are recorded below.

Regenerate the lock only from the flake inputs and validate it; never add lock
nodes or `narHash` values by hand:

```bash
nix flake lock
bash checks/component-lock.sh components/desktop-m1.json components/desktop-m1-baseline.json flake.lock
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

## Desktop Milestone 2 VM deployment — 2026-08-24

Commit `1aa712237c60494b2690eccc75aaa37a87225a03` was exported from a clean
worktree. Its public `git archive` SHA-256 was
`c71aabbb388116c6541dfcbb5b1951c74ee827c1df31fe83355e2c8d7ef62952`;
the complete Git bundle SHA-256 was
`d8c3f935e268e6797fb96398b1731a725e610ca6a7902640cf47c42bfe10ab71`.
That deployment source commit was pushed to and remains an ancestor of the
public branch `feat/desktop-m2-control-center`.

The clean-copy `nixos/nix:2.35.2` gate ran with `/dev/kvm` and ended with
`all checks passed!`. It included the real M1-to-M2 QEMU update test, the exact
Niri 26.04 validator, component ownership and lock contracts, Home Manager,
session, artwork, desktop QML/package/preview, GPL-scope, and source-clean
checks.

The VM first activated the reviewed candidate reversibly. After live visual
inspection it was permanently switched, rebooted, and inspected again. Both
`/run/current-system` and `/nix/var/nix/profiles/system` now resolve to:

```text
/nix/store/m1jxcyb71nkxl6s0m0hn2rxkrpav29rf-nixos-system-sleepy-vm-26.11.20260822.2c423e0
```

The reboot preserved the three user-owned artifacts byte-for-byte:

| User-owned artifact | Accepted SHA-256 |
|---|---|
| `~/.config/sleepy/settings.json` | `d8d0c1695362be643d00b8f1b9cc1acbb3b3abb6dc2dc63fe56acb570ec217a0` |
| `~/.local/state/sleepy/presets.json` | `07bbad19c9c777e00a67651b41865cf251ef28877eafde550664c632b9103c01` |
| `~/.config/niri/sleepy-user-bindings.kdl` | `9aa7b9a9058b247a4e4dbefdf51849e9fc4a759f4909afe1fa789e119932698d` |

After the reboot, Niri, `sleepy-session`, `sleepy-bindings-online`, and
Quickshell were all active. Quickshell carried
`QML_XHR_ALLOW_FILE_READ=1`; its current-boot journal contained no local-file
XHR, `QML Image:`, or unsupported-image-format error. The active user preset
was `Sleepy M2 Preview`, and both its contract and the generated KDL bound
`surface.controlCenter.toggle` to `Mod+Space`. A real guest `Mod+Space` input
opened the drawer; a second input closed it.

The first untouched post-login frame contained only the lunar rail and no
Niri hotkey overlay. The live drawer showed the glass surface, logical SVG
icons, network/Bluetooth, volume/microphone, brightness, mute, night-light,
power-profile, media, preset, and diagnostics widgets. Named-preset and
keybinding pages rendered and were navigable. The power chooser opened without
performing an action, and Cancel returned safely while the session remained
active. Captured guest-frame hashes were:

| Frame | SHA-256 |
|---|---|
| Clean post-reboot desktop | `ffa42ebe7488ce96b735756c83a9f556a9164bfdc20ec947028add26e7a767f0` |
| Drawer opened by live `Mod+Space` | `3b497eba461cb5e8b4d5b271dffa4b21565d54033a176713c24e4857871b60dc` |
| Safe power chooser | `a5bef49c0b7a1f1704973d9f5241c5acb713be9f4b224ed2fe8f7db08308e279` |

No system generations were deleted and no garbage collection was run.

## Desktop Milestone 1 VM deployment — 2026-08-24

Commit `0267c7bba0ed9d4ac3360583d7a6726c865f6b47` was exported as a
clean public archive with SHA-256
`d9205eda068d04b4ca6acb2de977f1c25f029e69610e138d274bd0e323099f02`.
The archive contained only regular files and directories. Source-clean and
component-lock contracts passed after root-owned extraction in the VM, and a
full VM `nix flake check` ended with `all checks passed!`.

The candidate was dry-activated and test-activated before the permanent
profile changed. The test activation produced toplevel
`/nix/store/12mhf8a8cjcfz889srfldgnm2zgf7hal-nixos-system-sleepy-vm-26.11.20260822.2c423e0`
while the previous permanent profile and generation set stayed unchanged.
After SSH reconnect, graphical service and state checks passed, then the
reviewed permanent switch created exactly `system-6-link` for that toplevel.
Generations 1 through 5 were retained; no generation deletion or garbage
collection was performed. The previous source tree remains at
`/etc/sleepy.pre-0267c7b-20260824T023543Z`.

The deployment initialized the previously absent settings and preset stores,
then preserved their inode metadata and exact contents across dry, test, and
permanent activation:

| User-owned file | Accepted SHA-256 |
|---|---|
| `~/.config/sleepy/settings.json` | `a1d575f14b75c650b5b9c9651c7efe7e156a66dc52ec8233643bcca4b426cabf` |
| `~/.local/state/sleepy/presets.json` | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |

Fresh post-switch checks proved SSH reconnect, matching runtime and permanent
profile, responsive Niri, active `graphical-session.target`, healthy
`quickshell.service` with zero restarts, and successful
`sleepy-session.service`. The Home Manager shell link resolved to the external
`sleepy-shell-0.1.0` store package, and the packaged SDK accepted the deployed
settings document.

The final 1280×800 guest framebuffer showed the inset lavender rail, lunar
mark, active workspace, clock, and status control aligned and rendered without
visible clipping; the captured screenshot SHA-256 is
`e12344e75cded2ac4ffe0604cf5ac5d4486d86f9407b9bb597aab23af65d4802`.
Host-side VNC and libvirt input did not activate the QML status control, so a
live drawer screenshot was not obtained. Drawer behavior remains covered by
the component test suite but is explicitly not marked as live visual PASS.
Consequently, the fallback-deletion gate remains closed.

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
