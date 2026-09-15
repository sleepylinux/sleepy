# Usable alpha validation in progress

This record covers the daily-usability candidate. It does not replace the
[accepted installer ISO](installable-alpha.md) until a complete installed-disk
run passes for the new production graph.

## Implemented and targeted checks

- Conservative absent-hardware providers: session `004e81d`, component CI
  [34911942420](https://github.com/sleepylinux/sleepy-session/actions/runs/34911942420)
  passed. Follow-up `2e85655` fixes the captured UPower absence response;
  its signed runtime was checked on the existing disposable disk below.
  Fresh combined-image acceptance remains pending.
- Original terminal crescent: artwork `ac3feed`, merged PR #6; exact-head CI and
  real Fastfetch 80/120-column plus monochrome renders passed.
- Shared GTK/terminal appearance, image viewer, Fastfetch and screenshot keys:
  real Home Manager override assertions evaluate successfully. Actual combined
  installed-desktop rendering and screenshot roundtrips are pending.
- Optional hardware/software profiles: base, Bluetooth, Flatpak, development,
  gaming, NVIDIA and combined configurations evaluate successfully. Physical
  hardware and real game performance are not covered by this matrix.

## Flatpak registration regression

Production change `ad9e3599fcf0b071765115310352663ce7b1503a` was exercised in
separate fresh disposable KVM guests. The old unit failed to retry registration
within 30.30 seconds after the controlled remote operation recovered. The new
unit passed in 69.46 seconds: retry after error, no repeat after success, bounded
stalled process while login remains independent, child cleanup and recovery.

The test replaces only the remote operation and accelerates the timer interval
to two seconds. Production process deadlines remain 45 seconds to start and
five seconds to stop. This proves systemd scheduling and cleanup; public
Flathub and graphical Software installation require separate acceptance.

Reproduce with `nix build .#checks.x86_64-linux.flatpak-recovery --max-jobs 1 -L`.
[Provenance](assets/usable-alpha/flatpak-recovery.txt),
[old-unit failure](assets/usable-alpha/flatpak-recovery-red.log),
[new-unit pass](assets/usable-alpha/flatpak-recovery-green.log).

## Combined VM

Candidate ISO `7231d4b2bf320440365b0f51a323f3466c724dd1` completed real TUI
installation, installed-disk boot, password login, application mapping and crash
recovery. A first boot with the NIC disconnected before firmware execution
failed its first Flathub registration, then the unchanged production timer
registered the real public remote after networking returned.

The combined run **failed** waiting for the visible password field after
locking. The protocol reported locked, but the captured framebuffer still
showed the earlier desktop. A separate diagnostic confirmed DPMS stayed off
until ordinary Shift input; the runner now wakes graphical input before
selecting its keymap. See the [wake evidence](assets/usable-alpha/candidate7231-wake-README.md)
and [input-readiness evidence](assets/usable-alpha/candidate7231-keymap-README.md).
The original run remains failed; no full daily, screenshot, update or reboot
acceptance is claimed for this candidate.
[Partial evidence and exact revisions](assets/usable-alpha/candidate7231-README.md).

A subsequent candidate also includes the installer VT palette and dark ReGreet
preference. Those changes have Nix evaluation and override checks, but still
require a fresh image and visible installed-VM verification.

## Corrected provider runtime on the existing disk

On the same installed `7231d4b` disposable disk, a temporary user-service
`ExecStart` override loaded session `2e85655df116851781b79fc80403381eedef99c3`:
`/nix/store/6h6xv9jwvirbhgkxsjh7v3qamgcq61v5-sleepy-session-0.1.0`.
It was built from public root `d3252c67f09618414ca2d33aeb776e75246c3f26`
(491 release tests passed, two existing tests ignored), transferred through the
existing signed cache, and verified without changing its public key or trust
requirements.

The [actual doctor JSON](assets/usable-alpha/candidate7231-session2e85655-doctor.json)
reports `ok: true`, audio available with the VM's virtual audio device, Bluetooth
unavailable, and battery unsupported. The captured UPower 1.91.3 absence
response now classifies correctly. Screenshot helper remains unavailable;
this report does not prove the separate shell screenshot workflow. It is a
summary of daemon capabilities, not proof that every operation succeeds.

This was a diagnostic runtime override on an older installed image, with
additional locker diagnostic instrumentation active. It is **not** a fresh
installation of the corrected production graph, an update/rollback test, or
proof of a completed native-lock or screenshot roundtrip. The original failed
combined result remains unchanged. Only the doctor JSON was extracted from the
mixed diagnostic report; command echoes and locker debug messages were omitted.

## Fresh migration VM and dconf

Root `d3252c67f09618414ca2d33aeb776e75246c3f26` passed the isolated fresh
NixOS migration VM check in 44.01 seconds. Its assertions read the actual user's
dconf database and require `prefer-dark`, alongside the existing Home Manager
migration and rollback/state-preservation checks. The fixture explicitly enables
the dconf writer service needed by standalone Home Manager.

[Compact execution log](assets/usable-alpha/d3252c-dconf-migration.log) and
[exact result/source provenance](assets/usable-alpha/d3252c-dconf-migration.json)
are preserved. Reproduce with
`nix build github:sleepylinux/sleepy/d3252c67f09618414ca2d33aeb776e75246c3f26#checks.x86_64-linux.update-safety-vm --max-jobs 1 -L`.
This is a migration fixture VM, not the final installed-desktop acceptance.

## Follow-up screenshot and system-menu diagnostics

On the same `7231d4b` installed disk, with the temporary session `2e85655`
package above, actual Print input opened the existing area picker and Swappy.
Saving produced a complete PNG, and `xdg-open` mapped imv. Shift+Print then
replaced a fresh text-only clipboard sentinel with a complete PNG. The
[execution markers](assets/usable-alpha/candidate7231-screenshots-live.txt),
[Swappy screenshot](assets/usable-alpha/candidate7231-screenshots-live-3.png), and
[viewer/clipboard screenshot](assets/usable-alpha/candidate7231-screenshots-live-completed.png)
record this bounded live UI check. PNG persistence across reboot was not tested
in this diagnostic. The unavailable SDK screenshot helper is a separate path.

The same session ran the explicitly transferred signed package
`/nix/store/qlv3rzwssa10fi8sqwvkqp6sj5m9kllh-sleepy-system` as the ordinary user.
Status and generation listing succeeded, its actual terminal menu appeared,
and Esc closed it without changing generations.
[Execution markers](assets/usable-alpha/candidate7231-system-menu-live.txt) and
[visible menu](assets/usable-alpha/candidate7231-system-menu-live-0.png) are retained.
This check did not invoke rebuild or rollback.

Later, a temporary `ExecStart` override loaded session
`4d48082a0ff22cfefa6ebd007f41b6192709aa27` from signed package
`/nix/store/w3ayrd6cmyx178pk01iwb3ggdr4x3sws-sleepy-session-0.1.0`.
An actual typed suspend-then-hibernate request was rejected without locking.
The [response and assertion](assets/usable-alpha/candidate7231-session4d48082-unsupported-sleep.txt)
and [earlier login1 capability response](assets/usable-alpha/candidate7231-sleep-capability.txt)
record the unsupported operation (`CanSuspendThenHibernate` returned `na`).
This does not prove a supported suspend/resume cycle.

These are separate diagnostics on the old disk, with runtime overrides and
locker instrumentation. They do not replace its failed combined acceptance,
and do not demonstrate the pending Qt keyboard-focus fix. Exact component
revisions, package paths and source-log/script hashes are in the
[provenance manifest](assets/usable-alpha/candidate7231-daily-ui-provenance.json).

## Fresh production greeter regression

Public root `2f3755622c5af450046dc57dfe51e9b01ef8f2d2` passed a fresh
`hyprland-production-vm` in 118.93 seconds. The gate checks visible ReGreet
readiness, exact persisted session selection, actual UWSM launch and its user
unit, shell/daemon socket ownership and restart recovery, plus migration-state
preservation. It avoids using OCR of small text as a session identity check;
regressions still reject the direct Hyprland session and wrong user.

[Compact execution proof](assets/usable-alpha/2f37556-production-vm.txt) is retained.
Reproduce with
`nix build github:sleepylinux/sleepy/2f3755622c5af450046dc57dfe51e9b01ef8f2d2#checks.x86_64-linux.hyprland-production-vm --max-jobs 1 --cores 1 -L`.
This existing fixture uses credential-free test-only PAM. Its pass is separate
from real-password installed-disk acceptance and does not complete the final
combined usability gate.

## Actual Software installation and native locker focus

Further diagnostics used the same old `7231d4b` installed disk and temporary
session `4d48082` runtime. GNOME Software displayed Kalk from real Flathub,
installed it, changed its action to Open, and launched the calculator. The
visible calculation produced `4`. Evidence:
[before installation](assets/usable-alpha/candidate7231-software-calculator-details.png),
[installed Open action](assets/usable-alpha/candidate7231-software-after-unlock.png),
[running calculation](assets/usable-alpha/candidate7231-kalk-calculation.png), and
[Flatpak ref, commit, origin and mapped window](assets/usable-alpha/candidate7231-kalk.txt).
This proves this application flow, not all portals, keyring/polkit behavior or
all Flatpak applications. Kalk used a light theme in this capture.

The Qt keyboard-removal fault was reproduced in Qt's existing Wayland client
suite: unpatched Qt lost the focus window after capability removal/re-addition;
the same test executable with the patched library passed all five checks.
[Compact red/green output](assets/usable-alpha/qt-keyboard-focus-red-green.txt)
records the permanent regression. The maintained
[downstream patch and rationale](../../packages/vendor/qt-wayland-focus/README.md)
are scoped to the native locker; this is not an upstream-accepted fix.

An earlier instrumented source-patched Qt build restored active-window and
prompt focus after VT return, followed by real native password unlock.
[Filtered focus events](assets/usable-alpha/candidate7231-native-focus-observer.json)
exclude input lengths and authentication details. A later diagnostic loaded
clean Qt library `s7n4mf856bmrmqz1i3q9v54giy2gfyqc` with dark native locker
`815b403b5016a41027b396b0c5efac6a5160cb6e`: after VT return, Russian input reached
the masked field, switching back to US permitted real-password PAM unlock.
[Dark locker after VT return](assets/usable-alpha/candidate7231-dark-locker-vt-russian-input.png)
and [unlocked status with actual mapped libraries](assets/usable-alpha/candidate7231-native-focus-unlock.txt)
are retained.

These temporary guest overrides demonstrate the fixes on an existing installed
system. They are not fresh final-image acceptance or proof that every user
service is healthy. [Exact provenance and source hashes](assets/usable-alpha/candidate7231-kalk-qt-provenance.json)
distinguish the earlier instrumented Qt build from the clean later library.
The final combined installation, locked VT roundtrip, update and reboot gate
remains required.

The existing guest already demonstrated real Secret Service store/lookup with
its PAM-unlocked login collection before removal of the malformed auxiliary
keyring unit; no earlier storage failure is claimed. The daily runner now
requires an unlocked collection, rejects `bad-setting`, discovers `secret-tool`
from the installed closure, and stores/compares a fixed nonsecret test value
without printing it. On subsequent boot it only reads the previous value, so a
rewrite cannot hide lost persistence. Calls are bounded to ten seconds. Shell
protocol regressions pass; this new reboot assertion awaits the final VM run.

### Network refresh and daily authentication follow-up

The old shell repeatedly treated `nmcli radio wifi` reads as mutations and
retained finished Process objects. An actual 6.6 GiB OOM and exec trace
identified the loop. Desktop `f91f71e` classifies positional commands and destroys
finished Process objects. The exact packaged shell then completed a 20-minute
installed-VM soak with zero restarts, about 454 MiB RSS and 27.49 CPU seconds.
[Samples](assets/usable-alpha/f91-packaged-shell-20min.jsonl) and
[provenance](assets/usable-alpha/f91-packaged-shell-soak-provenance.json)
record this temporary runtime override, not a fresh final-image boot.

Firefox opened the saved PNG through the real FileChooser portal (response 0),
and the native polkit dialog accepted the created password for a read-only
authorization check. [Trace and screenshot provenance](assets/usable-alpha/candidate7231-network-loop-portal-provenance.json)
records the earlier diagnostic shell used for those actions. The final image
remains gated on a clean install, keyring persistence and update/rollback.
