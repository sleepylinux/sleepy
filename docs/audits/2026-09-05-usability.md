# SleepyLinux usability audit — 2026-09-05

The read-only baseline review covered root commit `f09d320`, local source,
existing acceptance evidence and root shell fixtures. Follow-up implementation
and runtime review used isolated Nix profiles, disposable QEMU disks and pinned
component sources. The host installation was not rebuilt or activated.
Historical findings below are followed by implementation and acceptance results.

## Baseline conclusion

At the baseline, SleepyLinux provided a pre-alpha NixOS desktop integration, not a
complete independently installable distribution. The desktop had substantial
automated coverage. Installation, package management UX, release updates and
hardware acceptance required separate deliverables before general daily use.

## Baseline findings before implementation

| Priority | Finding and evidence | Required resolution |
| --- | --- | --- |
| P0 | `flake.nix` exports only `sleepy-vm`; `hosts/sleepy-vm/hardware-configuration.nix` fixes the root/ESP UUIDs and the host chooses user `lazy`. No ISO or installer output exists. | Provide a documented installation route and reusable host template, then an installer tested on disposable disks. Never reuse this VM's UUIDs on another machine. |
| P0 | `modules/nixos/base/default.nix` creates a user but provides no fresh-install credential provisioning. Existing-machine passwords can survive, which is different from first installation. | Installer must provision the chosen account and authenticate it on first boot; test wrong/empty passwords and recovery login. Do not introduce a shared default password. |
| P0 | No `snug` implementation or package exists. Package installation is not documented in README. | Ship user package search/install/remove/list/update/rollback with clear errors and desktop launcher integration. |
| P0 | No release updater is implemented in root. Deployment is a manual source transfer/build/test/switch procedure in `docs/deployment.md`. | Define release source, host configuration ownership, candidate build, activation, retained generations, failure handling and recovery; expose it through snug. A package-profile update is not an OS update. |
| P0 | Current acceptance explicitly remains PARTIAL in `docs/acceptance/hyprland-sleepy-desktop.md`. Real-password auth, secure suspend/resume, screencast, bootloader rollback and recovery evidence remain open. | Execute acceptance against exact release revisions. Automated fake-PAM greeter tests do not establish password security. |
| P1 | No `nix.settings.experimental-features` configuration exists although documented deployment uses flakes. Several examples omit the flags required on a default installation. | Enable `nix-command` and `flakes` declaratively; test the evaluated system configuration. |
| P1 | No file manager, default directory MIME handler, or explicit udisks2/GVfs integration is configured by root modules. | Install/configure a file manager and removable-media integration; test directory opening, mounting and safe eject in a user session. |
| P1 | `modules/home/hyprland/binds.nix` has media playback keys but lacks volume, mute and brightness keys. | Add commands using packaged providers and test bindings; verify on a laptop. |
| P1 | `docs/recovery.md` describes `niri.service`, `quickshell.service`, old bindings and historical generation numbers. Current units are UWSM's `wayland-wm@hyprland.desktop.service`, `sleepy-shell.service`, `sleepy-session.service` and `sleepy-locker.service`. | Rewrite current recovery first; retain clearly labelled historical migration evidence. |
| P1 | VM has no swap or resume configuration; session exposes guarded hibernate/suspend-then-hibernate operations. | Define supported sleep modes for each installation and test unavailable-capability behavior. Do not advertise working hibernation from a successful API call alone. |
| P1 | No general hardware installation/validation evidence is present. | Validate chosen Intel/AMD/NVIDIA scope, Wi-Fi, Bluetooth, audio, external displays, battery, firmware, suspend and boot on target machines. |
| P2 | `supportedSystems` derives only from the x86_64 VM baseline. | State x86_64 support explicitly; add other architectures only with evaluated/buildable configurations and acceptance. |
| P2 | Strict external desktop parity is documented as failing; manifest/reference acceptance is incomplete. | Decide whether exact Caelestia parity is a product requirement. Track it separately from basic usability. |

P0 means a blocker to claiming a generally installable and recoverable release,
not necessarily a crash on the existing development VM. Absence of explicit
root configuration does not prove absence of a transitive dependency.

## Package installation today

Permanent declarative packages belong in `environment.systemPackages` or
Home Manager `home.packages`, followed by rebuilding the chosen configuration.
For a personal package on an existing installation:

```sh
nix --extra-experimental-features 'nix-command flakes' profile install nixpkgs#hello
```

This uses the Nix registry's nixpkgs source, not necessarily Sleepy's locked
nixpkgs. Do not mix `nix-env` and `nix profile` in the same profile. In particular,
a Home Manager owned profile must not be treated as snug's mutable package list.
The CLI needs a separate owned profile and must expose its binaries and desktop
entries to both the shell and UWSM session.

Reference: [Nix profile manual](https://nix.dev/manual/nix/2.19/command-ref/new-cli/nix3-profile).

## Initial snug design (superseded by the implemented command reference)

Recommendation: a small Python standard-library CLI packaged by Nix, delegating
store operations to Nix. Nix already supplies builds, dependencies and profile
generations. Reimplementing those would create a second package manager to
maintain. A GUI-first approach adds presentation work before the update and
recovery model is defined; the same CLI/backend can later serve a GUI.

Initial proposed commands (use [the current reference](../snug.md) for implemented syntax):

```text
snug search firefox
snug install firefox ripgrep
snug remove firefox
snug list
snug run hello
snug shell nodejs git
snug dev init python
snug dev                         # enter the project environment
snug dev update                  # deliberately update its lock
snug update                      # personal applications
snug rollback                    # personal profile generation
snug system update               # OS candidate, build and activation
snug system generations
snug system rollback
snug doctor
```

### Package ownership

Use a dedicated XDG state profile, leave Home Manager's declarative packages
owned by Home Manager, and explain ownership in list/remove failures. Pass
subprocess arguments as arrays. Reject ambiguous names and option injection.
Serialize mutations and preserve prior generations; no automatic garbage
collection. Display actionable diagnostics for missing commands, unavailable
network/cache, unfree packages and interrupted operations. Configure PATH and
XDG_DATA_DIRS so installed GUI applications appear in the launcher.

### Development environments

Generate a project `flake.nix` and real Nix-generated `flake.lock`; enter using
`nix develop`. Initial presets: Python, Node and Rust with an explicit package
list. Refuse to overwrite existing project files. Existing project flakes are
supported directly. Language package installation belongs to the project tool
(pip/uv/npm/cargo); system package installation does not replace it.

### System updates

OS updates must follow a chosen Sleepy release source and preserve host-specific
hardware, users, stateVersion and local customisation. Do not treat `nix flake
update` against all component pins as a new reviewed Sleepy release. Build an
immutable candidate before privileged activation; keep the previous generation
and recovery instructions. Fetch/build failures must not change the boot profile.
Activation failure needs an explicit recovery result, not a success message.
Privilege escalation occurs only for system operations through normal PAM.

The release source/channel and whether updates apply live or on reboot need a
product decision before implementing this interface.

## Validation recorded in this audit

Executed every `checks/*-test.sh` locally: 17 returned exit 0. The remaining
`checks/vm-acceptance-assets-test.sh` returned 127 because `pngcheck` is missing
on the host. That is an environment prerequisite failure, not an established
product defect. Nix is not installed on the host; Docker and `/dev/kvm` exist.
Nix 2.35.2 container evaluation of the baseline subsequently passed with no lock changes.
No new full flake build, live desktop check or hardware acceptance is claimed.

## Implementation and acceptance order

1. Implement snug package operations and dev environments with subprocess,
   failure and filesystem-preservation tests, plus a real isolated Nix profile
   lifecycle test. Package it, export it and integrate session paths.
2. Fix current desktop usability gaps and recovery documentation. Add evaluated
   Nix assertions and appropriate functional checks.
3. Implement OS updates once the release/configuration ownership is settled;
   validate failed build, failed activation, retry, reboot and rollback in a VM.
4. Deliver the agreed installer scope and fresh-machine credential setup using
   disposable disks. Verify reboot, login and local configuration preservation.
5. Run the hardware and manual acceptance matrix; publish only supported claims.

## User decisions and implemented scope

The user chose a CLI with short and long flags, rolling updates, broad hardware
including NVIDIA, and a minimal bootable ISO with terminal onboarding and package
categories. All documentation and product text must be English. The command
contract lives in [docs/snug.md](../snug.md), shipped with the snug package.

Implemented in this worktree:

- Snug personal package profiles, install/remove/search/list, temporary `-it`,
  run/shell, locked Python/Node/Rust dev environments, update/rollback and full
  Nix passthrough. Short operations have long equivalents and built-in help.
- Root-owned staged rolling system update, build before activation, generation
  recovery on failure and source-lock-aware rollback without deleting history.
- A minimal online x86_64 ISO with a curses installer, package categories,
  driver discovery/override, account setup and explicit disk confirmation.
  Full configuration evaluation runs before partitioning. Identity is checked
  again afterward. BIOS GRUB uses a verified persistent by-id path.
- Declarative Intel/AMD/NVIDIA and PRIME configuration, reusable host template
  and documented manual installation for custom disk layouts.
- Enabled flakes, file manager/removable-media integration, sound/brightness
  shortcuts, and current Hyprland recovery instructions.
- Unit/process safety checks, a real local-Nix package lifecycle check, evaluated
  NixOS assertions and CI coverage for new tests and ISO builds.

## Remaining acceptance and product limits

These are not closed by source changes or unit tests:

- Full current-revision desktop, real-password, secure suspend/resume,
  screencast/recording, bootloader rollback and hardware acceptance matrix.
- Broad vendor configuration does not establish support for every NVIDIA
  generation, firmware implementation, hybrid wiring or ARM machine. Initial
  ISO and integrated root checks target x86_64.
- Automated installer storage is whole-disk GPT/ext4, without encryption, swap
  or dual boot. Custom storage uses the documented manual route. Hibernation
  requires separately configured and validated resume storage.
- No exact-pixel Caelestia parity claim, signed Secure Boot installation, offline
  complete desktop bundle, or application-data rollback is made.
- Package installation from the ISO is declarative system configuration;
  personal snug removal does not rewrite that system package list.

Build and VM evidence must identify the actual tested source/ISO. The historical
acceptance records remain historical and are not rewritten as fresh passes.

## Implementation verification

The implementation has passed 81 Python tests covering the CLI, staged system
updates, desktop-entry projection, installer and fresh shell defaults. The real
Nix 2.35.2 profile lifecycle passed install, temporary shell, update, rollback and
remove in an isolated profile. Evaluated hardware/usability checks and the root
source-contract fixtures passed. The real systemd runtime-directory VM passed
both service stop/start directions, including surviving socket inode, PID and
request/response checks. Formatting, Statix, Deadnix and ShellCheck passed.

A bootable ISO was built and reached onboarding under BIOS and UEFI/OVMF.
UEFI reached onboarding after a prolonged boot delay and exposed console
Unicode differences. Text-mode GRUB makes the selected boot entry visible;
ASCII UI separators render consistently. Text mode is not evidence that the
entire firmware/kernel loading delay has been eliminated.
The full disposable installation exposed an unreliable filesystem autodetection
immediately after formatting; explicit ext4/vfat mount types fixed it and have a
regression test. Full first-boot acceptance remains pending until recorded below.

See [the independent subagent review](2026-09-05-independent-review.md) for
confirmed findings and the distinction between source fixes and acceptance.

The 6 GiB installation VM exhausted memory during four-way Quickshell source
compilation. The installer now passes `--max-jobs 1 --cores 1` to nixos-install,
with a regression test; the disposable installation is resumed without reformatting.

Release performance gate: no Sleepy-specific binary-cache URL or public signing
key is configured in this work. The actual installation compiles the pinned
Quickshell build. A release cache for those closures would substantially reduce
first-install time and memory use; its location and signing ownership need to
be supplied before it can be trusted by the ISO or installed systems.

Final keyboard review found that RU-only desktop input had no Latin-layout
switch. The RU choice now generates `us,ru` with `grp:alt_shift_toggle`; both
the generator regression and evaluated NixOS/Home Manager settings pass.

## First installed boot finding

The disposable BIOS installation reached ReGreet and normal-user TTY login
succeeded. The first graphical default was the raw `hyprland.desktop`, despite
UWSM being enabled. Authentication succeeded but only a blank compositor
appeared: `graphical-session.target`, `sleepy-session.service`,
`sleepy-shell.service` and `sleepy-locker.service` were all inactive. This is a
confirmed first-use blocker, not a cosmetic session-label issue. A managed
session default and fresh-login verification are required to close it.

Explicitly selecting `Hyprland (uwsm-managed)` produced the actual Sleepy
desktop without software-rendering overrides. The pinned ReGreet has no
configurable initial session, so Sleepy now patches only its uncached fallback
to prefer the managed entry when present. Existing saved user choices and the
underlying raw entry remain intact. Evaluated wiring/source checks pass; the
patched binary and fresh-cache graphical login are being validated separately.

## Sustained desktop runtime finding

A longer run of the installed managed session exhausted the 6 GiB VM: the
kernel killed `sleepy-shell.service` with approximately 4.8 GiB anonymous RSS.
This blocked acceptance until the cause and the package fixes recorded below
were verified. A successful first desktop frame does not establish stability.

Separately, an audio refresh feedback loop was confirmed in the pinned session
backend. Every line from `pw-mon` triggers an audio probe; those read-only
PipeWire clients themselves generate monitor events. With the shell stopped,
a bounded pause of only `pw-mon` reduced process creation from about 52 to 34
forks per second. The daemon itself stayed near 15 MiB RSS. This proves an
avoidable audio polling loop, but does not establish the cause of the shell's
memory growth. The remaining probes include supervised periodic providers.

Source review then found a separate concrete shell defect in `Nmcli.qml`:
`isMutationCommand` treats the read-only `nmcli radio wifi` command as a
mutation. Its successful completion schedules `refresh()`, which calls the same
read again. Each command also allocates a parent-owned QML `CommandProcess`;
completion removes it from an array but never destroys the object. This is an
unbounded command loop with retained process objects. Regression and installed
runtime verification are required before closing the sustained-memory finding.

The compiled patched ReGreet was deployed to the disposable guest with the same
cage/DBus invocation and an empty greeter cache. Its default selection was
`Hyprland (uwsm-managed)` without session-menu interaction. The fresh-default
selection gate passed; sustained shell acceptance is tracked separately above.

The bounded audio refresh package built with its full Rust test suite:
478 passed, 0 failed and 2 ignored. The updated integration fixture changes
external audio state and checks the real daemon/OSD response while requiring
that the old `pw-mon` source is never started. The shell regression also
reproduced the radio-query loop and retained objects, then passed after the
network-command classification and lifecycle fix. Both fixes are explicit
reviewed downstream patches; see [patch provenance](../../patches/README.md).

## Secure unlock finding

Real-password testing accepted a wrong-password rejection, then exposed a
separate unlock blocker. With the correct password, the lock card animated away
but the session stayed locked. The installed journal recorded
`TypeError: Property 'unlock' of object WlSessionLock is not a function` at
`LockRoot.qml:58`. The pinned Quickshell class exposes the writable `locked`
property; its C++ `unlock` slot is private and not a callable QML method.

The fix must clear the existing `lockRequested` binding only after native PAM
success, a confirmed secure lock, and `endpoint.unlockAllowed`. It must retain
suspend holds and fail-secure lifecycle behavior. Native builds, a regression
check and another actual password/unlock test are required to close this finding.

Publication remains a release step: local worktree changes and the generated
ISO are not automatically merged into the default GitHub update source.
Maintainers must publish the tested revision before installed machines can
retrieve this work through the public rolling updater. The local-candidate
activation/rollback test does not establish publication of those changes.

The patched secure locker built successfully with both native/supervisor CTest
suites passing. The real pinned Quickshell API and extracted authenticated
handler regression fails on the original call and passes on the supported
binding transition, including secure/hold guard combinations and retained
binding behavior. A separate reviewer found no security-guard regression.

The installed VM with compiled shell, daemon and locker packages then reached
an idle-triggered native lock. Empty-password submission was rejected; the
correct normal-user password returned the desktop, and workspace switching
worked after unlock. This closes the observed private-API unlock failure.
The final sustained run and repeated-lock evidence are recorded alongside the
ISO, with the actual tested package store paths and virtual hardware.


## Final sustained runtime result

With the compiled patched shell, session daemon and locker, the disposable
VirtIO 3D VM completed 61 samples over 600.04 seconds. Shell RSS was 264,868 KiB
at the first sample and 274,696 KiB at the last, peaking at 275,344 KiB. The
unbounded memory growth did not recur; observed process creation was about
40.49 tasks/second, versus roughly 1,400/second in the faulty shell baseline.
This closes the reproduced recursive-refresh/process-retention OOM blocker,
not every possible long-duration or physical-hardware performance issue.

Two natural idle-lock cycles returned to a working desktop after the correct
normal-user password. Empty and wrong passwords were rejected, and workspace
switching worked after both unlocks. The final checks also cover exact patched
component provenance, the locker service/PAM wiring, the supported unlock API,
18 QML network-command lifecycle cases and the root source contracts.

The complete installation used a disposable BIOS disk and was resumed without
reformatting after the initial parallel-build memory failure. The final runtime
packages were installed through explicit test service overrides; they were not
misrepresented as an untouched installation of the final ISO. Exact ISO boot
and package/VM evidence lives in the artifact directory's BUILD.md and
verification/VM-ACCEPTANCE.md. Physical GPU, suspend/resume, UEFI disk installation
and public release publication remain the separately stated gates.

The accelerated virtual GPU exposed another practical compatibility limit:
Ghostty refused its OpenGL 4.2 renderer because it requires 4.3. Sleepy now also
installs the lightweight Foot terminal and binds it to `Super+Shift+Enter`,
providing terminal access without downloading a replacement or changing global
graphics settings. Ghostty remains available on `Super+Enter`. Evaluated Home
Manager and shortcut checks cover the fallback; the artifact report records
its actual launch in the same virtual GPU environment.

## VT keyboard lifecycle diagnosis

A further locked VT2/VT1 test exposed missing password input after return.
Restoring native QML item focus and resending focus at VT activation did not
resolve the installed VM failure; neither experiment is counted as a pass.
The final compositor patch replaces the ineffective activation hook.

Wayland tracing with dummy input showed keyboard capability removal followed
by destruction and recreation of the client's keyboard object. No keyboard
leave preceded removal. Qt made the window inactive, retained the same display
focus target, and ignored the subsequent same-surface enter. Key events reached
the client but did not reach the native secure prompt. This matches the exact
[Qt 6.11.1 keyboard destructor](https://github.com/qt/qtbase/blob/v6.11.1/src/plugins/platforms/wayland/qwaylandinputdevice.cpp)
and [display focus cache](https://github.com/qt/qtbase/blob/v6.11.1/src/plugins/platforms/wayland/qwaylanddisplay.cpp).

The replacement patch sends keyboard leave before removing the capability,
while the old protocol resource is usable. It preserves the compositor's focus
target so the normal new keyboard enter can restore activation. Passwords,
PAM decisions, suspend holds and lock ownership remain unchanged. Native QML
activation and mouse-focus regressions remain separate coverage; exact compiled
compositor VT acceptance is recorded in the artifact VM report.
