# Independent whole-project review — 2026-09-05

## Scope and conclusion

Reviewed the working tree based on root commit `f09d320`, including existing
NixOS/Home Manager integration, overlays and pinned component boundaries,
Hyprland/UWSM services, locker/session ownership, hardware options, Snug,
installer and ISO wiring, host templates, CI/checks, and recovery/acceptance
documentation. This was a separate review from implementation. Only this report
was edited by the reviewer; tests used disposable files, mocked commands and
read-only Nix evaluations. No installed system, disk or running user service
was changed.

The project has coherent NixOS integration and substantial automated checks,
but build/evaluation success is not a complete installation or daily-use gate.
The review found concrete defects in both existing desktop integration and new
update handling. Their dispositions below distinguish independently checked
fixes from work still underway and acceptance that requires a running machine.
This is not a line-by-line audit of every external Rust/C++/QML dependency.

## Findings and disposition

### R1 — P1: restarting the session removed the running locker's endpoint

Locations: `modules/home/session/default.nix:61`,
`modules/home/locker/default.nix:29`.

Both independent services used `RuntimeDirectory=sleepy` without preservation.
Stopping/restarting either service therefore permitted systemd to remove the
shared directory, including the other process's Unix sockets. In particular,
restarting `sleepy-session.service` unlinked `sleepy/locker.sock` even while the
locker process remained alive. A replacement daemon could reconnect its own
desktop clients but could no longer address that locker for protected actions.
The existing production VM restart test checked desktop stream recovery, not
survival of the peer locker endpoint.

This follows the cleanup in upstream
[`exec_context_destroy_runtime_directory`](https://github.com/systemd/systemd/blob/main/src/core/execute.c)
and the still-open [shared RuntimeDirectory issue](https://github.com/systemd/systemd/issues/5394).
It is an endpoint-availability defect; the review did not establish an unlock
bypass.

**Disposition:** implementation now sets `RuntimeDirectoryPreserve="yes"` on
both services. Independent evaluation confirmed both effective values are
`yes`; existing session/locker contracts pass. The added
`checks/runtime-directory-vm.nix` passed its real QEMU/systemd regression in
11.42 seconds. The reviewer inspected the test and completed log: both restart
directions preserve the surviving socket inode, process PID and live response.
Log SHA-256: `4dc9c1ae725942c47e2ef906dd0b037ae505c10333856f1bd528359f591ee14a`.
The test uses harmless peer servers and proves shared-directory lifetime; it
does not substitute for a real secure-lock/suspend test.
Preserved paths remain inside the private user runtime; final runtime cleanup
belongs to that runtime's lifecycle.

### R2 — P1: OS rollback could select a retained failed update

Location: `packages/snug/system_update.py:171`.

The original rollback selected the largest generation number below the current
one before consulting the update receipt. With good generation 1, failed
candidate 2 retained after restoration to 1, and successful update 3, rollback
selected failed generation 2 even though generation 3's receipt recorded
`previous=1`. It also skipped the corresponding source-lock restoration.
An isolated filesystem/subprocess-boundary reproduction printed
`Selected: system-2-link expected: system-1-link`.

**Disposition:** fixed. The current implementation reads the trusted receipt
first and uses its recorded previous generation. If that generation is missing,
it refuses to choose a different candidate silently. Numeric fallback remains
for generations without a Snug receipt. The independent rerun of all 18 system
update tests passes, including
`test_rollback_uses_last_active_generation_not_failed_intermediate` in
`checks/snug-system-test.py:100`. No live activation was performed.

### R3 — P1: default Sleep requires hibernation, but installation configures none

Locations: `packages/sleepy-installer/installer.py:184` and `:351`,
`docs/architecture/shell-runtime-integrations.md:63`, and the pinned
`sleepy-desktop` source at revision
`22f1cbe617e59b1d27e155c38c9a8e0bf5e7a3ac`:

- `src/plugin/src/Sleepy/Config/generalconfig.hpp:43` defaults the 600-second
  idle action to `suspendThenHibernate`.
- `src/plugin/src/Sleepy/Config/launcherconfig.hpp:115` gives the launcher Sleep
  action that same command.

The automated installer creates no swap or resume configuration. The session
provider invokes logind `SuspendThenHibernate`, without a plain-suspend fallback.
Systemd's [sleep capability checks](https://github.com/systemd/systemd/blob/main/src/shared/sleep-config.c)
require both suspend and hibernate for this operation and reject unavailable
hibernation storage. Thus ordinary suspend-capable machines can reject the
standard Sleep action on a default fresh installation. This is a mismatch of
defaults, distinct from whether a particular GPU resumes correctly.

**Disposition:** fresh-install defaults fixed in
`modules/home/session/default-shell.json` and `ensure-shell-config.py`, invoked
by Home Manager activation. Eight initializer tests pass independently. The
reviewer parsed the pinned native default records and compared all 13 launcher
actions and three timeouts: only the intended sleep commands/description differ.
`SessionActions.qml` resolves `["suspend"]` to the existing typed daemon action.
The supported user configuration is `$XDG_CONFIG_HOME/sleepy/shell.json`, with
`general.idle.timeouts` and `launcher.actions`. The create-if-absent initializer
seeds plain `suspend` for fresh installations while retaining the remaining
upstream actions and timeouts. These are whole arrays, so a one-element launcher
array would unintentionally remove other actions. Existing user configuration
must remain untouched; existing users retaining `suspendThenHibernate` still
need to choose a supported sleep action or provision and validate hibernation.

### R4 — P2: first personal GUI installation may not refresh the launcher

Locations: `modules/home/snug/default.nix:10`, `packages/snug/snug.py`, and pinned
Quickshell revision `0fed22a2c47d9568ddf13cf61586b3f2ac4378a2`,
`src/core/desktopentrymonitor.cpp`, `DesktopEntryMonitor::startMonitoring`.

Root correctly adds the dedicated profile's `bin` and `share` to the session
paths. However, the first profile normally does not exist when the shell starts.
The pinned desktop-entry monitor skips nonexistent application directories
before adding filesystem watches for their parents. Creating the first profile
later therefore need not generate a watched event or refresh the launcher.
An unrelated watched directory change or a shell restart may hide the issue.
Existing-profile upgrades have different behavior because the profile parents
were present when watches were installed.

**Disposition:** source fix integrated and independently reviewed. Home Manager
precreates `$XDG_DATA_HOME/snug/applications` during activation and puts its
stable parent before the profile share directory in `XDG_DATA_DIRS`. Successful
permanent install/remove/update/rollback operations refresh original-name
`.desktop` symlinks there while retaining logical profile targets across
generations; temporary environments do not modify the projection. Foreign files
and links are preserved, refresh conflicts are reported after the package change,
and `snug refresh` provides recovery. Eight projection tests and 18 CLI tests pass
in an independent rerun. These tests establish filesystem publication and code
ordering, not an actual Quickshell watcher event; running-shell acceptance is
still required. The real Nix CLI lifecycle test proves profile contents, not
GUI discovery. Acceptance must start with no Snug profile, install a small GUI
package during an already-running session, and verify appearance, launch,
upgrade and removal without requiring logout. Do not claim this gate from
`XDG_DATA_DIRS` evaluation alone.

## Earlier installer findings rechecked

The earlier username and BIOS disk-identity findings are not repeated as open
bugs:

- Reserved system users are rejected; complete selected configuration evaluation
  now runs before partitioning. The disk is scanned again after preflight.
  Tests cover reserved accounts, a failed evaluation before destructive commands,
  and changed media during preflight.
- BIOS configuration records an existing matching whole-disk
  `/dev/disk/by-id/...` identifier. Tests cover selection, partition-symlink
  rejection and a changed resolution. The earlier persistent `/dev/sdX` GRUB
  target has been removed.

A generated normal-user host with every offered application was independently
evaluated through `sleepy.lib.mkSleepyHost`: package attributes resolved and no
NixOS assertions failed. The normal account uses mutable credentials, root's
hash is locked (`!`) for the automated installation, and password provisioning
uses `chpasswd` stdin rather than command arguments. This confirms wiring, not
actual login/PAM acceptance.

## Verification performed

Independent bounded rerun during this review:

- `checks/snug-test.py`: 18 passed.
- `checks/snug-system-test.py`: 18 passed, repeated after the final receipt fix.
- `checks/snug-desktop-test.py`: 8 passed after stable projection integration.
- `checks/installer-test.py`: 21 passed.
- `checks/shell-defaults-test.py`: 8 passed; full seeded-default parity comparison
  against the pinned native defaults also passed.
- Hyprland session, user-config, locker lifecycle, root integration, desktop M3
  root and update-safety shell contracts passed.
- Actual Nix evaluation of `hardware`, `usability`, `locker-lifecycle` and
  `session-contract` derivations succeeded.
- Effective integrated Home Manager paths include
  `~/.local/state/snug/profile/bin`, `~/.local/share/snug`, and
  `~/.local/state/snug/profile/share`; the stable application setup runs from
  Home Manager activation.
- The prior isolated real-Nix experiment confirmed that `--override-input`
  needs explicit `--output-lock-file` to persist the staged lock, and that the
  implemented command refreshes the selected same-reference input.

The review also inspected the current system-update trust checks, fixed root
executable paths, stage/build/activation ordering, preserved generation and
lock receipts, hardware vendor branches, reusable template, ISO entry service,
source retention, and CI registration. No additional confirmed blocker was
established in those inspected paths. This is not a claim that the full CI build
or VM suite was rerun independently.

## Remaining release gates

These are missing evidence, not invented defects. The implementation run has
reported BIOS and UEFI ISO boots and is exercising a disposable-disk
installation, but full installed-system acceptance is still pending. Explicit
ext4/vfat mount types fixed the observed post-format autodetection failure and
passed the installer regression suite; this does not mark that installation
successful. Later CLI verification adds five --unfree tests (23 CLI tests total).

1. Build the final immutable ISO/configuration graph and record its checksum.
   Boot that exact image and perform an end-to-end installation to a disposable
   disk, including UEFI and BIOS boot paths. Reboot from the installed disk
   without the ISO and verify that its retained source/lock can evaluate.
2. Test chosen-user login and sudo with correct, wrong and empty passwords;
   root remains locked in the automated installation. Verify recovery access.
   Existing production tests use test-only PAM and do not establish this.
3. Exercise an actual successful OS update, failed activation, rollback and
   bootloader selection of the retained generation. Mocked subprocess tests
   prove ordering and restoration decisions, not bootloader/PAM behavior.
4. The shared-runtime systemd regression has passed. Run the full Hyprland
   production/update VM gates on the final changes.
5. Test secure lock, default Sleep, resume, locker crash, logout and session
   restart on the installed system. Validate any advertised hibernation separately.
6. Verify first-profile GUI discovery, Thunar directory opening, removable-media
   mount/eject, file chooser and screencast portals in a live user session.
7. Complete the stated Intel/AMD/NVIDIA hardware matrix: compatible driver and
   kernel, displays, Wi-Fi, Bluetooth, audio, brightness and suspend/resume.
   Successful option evaluation is not device compatibility evidence.

README correctly calls Sleepy pre-alpha. The existing acceptance record remains
explicitly partial and distinguishes historical evidence from current source.
Those qualifications should remain until the corresponding gates have fresh
results; source checks and an ISO build alone do not justify general daily-use
or exact visual-parity claims.

## Additional runtime findings and independent patch review

The installed-VM follow-up found a blank first login from ReGreet's uncached raw
Hyprland selection, an audio monitor/probe feedback loop, and sustained shell
memory exhaustion. Detailed reproduction and acceptance results are in the
[usability audit](2026-09-05-usability.md).

The shell defect was independently confirmed against the pinned QML source:
`nmcli radio wifi` is a read, but the old classifier treated any `radio`
argument as a mutation and scheduled another refresh. Each refresh allocated
new parent-owned command objects; completed objects were removed from the
tracking array without destruction. The downstream patch inspects command
positions and releases finished objects in the completion path, including
callback exceptions. The regression harness executes the actual production
functions in Qt and verifies both read behavior and QObject destruction.

A separate reviewer inspected that patch, its tests and root package wiring.
No additional runtime blocker was found. The review did identify a weakness in
the first downstream-provenance check: matching source, patch lists and
passthru metadata alone would allow unrelated build overrides. The check now
also requires exact equality with the upstream derivation overridden only by
the explicitly reviewed patch list. Saved package provenance includes patch
names and SHA-256 hashes. Upstream immutable component pins remain unchanged.

The audio patch passed its full package suite (478 passed, 2 ignored). It uses
bounded, coalesced refreshes and retains the existing mutation authority and
shutdown handling. It does not introduce an actor-local state cache that could
miss a transition after an intervening mutation.

The actual correct-password unlock test then exposed another independent P1:
the native locker called a private, QML-inaccessible `WlSessionLock.unlock()`
slot. The journal's `TypeError` explained why the password card disappeared
while the session remained locked. The one-line downstream fix clears the
existing `lockRequested` binding only inside the original authenticated,
secure-lock and suspend-hold guards. A different reviewer found no weakening
of PAM, holds, surface ownership or supervisor behavior. Both native CTest
suites and the pinned real-QML API/guard regression pass; the latter reproduces
the original TypeError. Actual unlock and subsequent re-lock are a separate
running-VM acceptance gate.

Follow-up actual patched-locker acceptance: the installed normal user reached
idle lock, an empty password was rejected, and the correct password returned
the desktop with working workspace switching. This closes the observed
private-API unlock blocker. The final artifact evidence records the repeat-lock
and sustained-session results without substituting them for physical GPU or
suspend/resume acceptance.


Final runtime follow-up completed 600.04 seconds with compiled patched packages:
RSS 264,868 → 274,696 KiB (peak 275,344 KiB), and two actual idle-lock/unlock
cycles with empty/wrong password rejection and working desktop controls after
unlock. This closes the reproduced shell OOM and private-API unlock findings.
The virtual hardware, service overrides and release/hardware limits remain
explicit in the adjacent artifact acceptance report.

## Additional VT focus review

Independent source review traced the installed VM's keyboard loss to capability
removal without a preceding keyboard leave and Qt 6.11.1's retained display
focus cache. A VT activation resend was built and failed the actual regression;
the replacement emits leave before the protocol capability changes. It does
not select another surface, authenticate, unlock, or modify suspend holds.
Review and native builds alone do not close this regression: the artifact
`verification/VM-ACCEPTANCE.md` records the compiled-package A/B result.
