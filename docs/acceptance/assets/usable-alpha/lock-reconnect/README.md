# Lock request lost during daemon reconnect — actual disposable-VM diagnosis

Original failed acceptance remains [failed-result.json](failed-result.json). This diagnosis does not turn it into a pass.

Installed candidate: `25376439913bb80fd0cf317169c2626ae6776ce8`.
Desktop: `45f721a037693523ba1886eba20784ac9e8102fc`.
Session: `210cbaad7a50280e4406281f90cbe36def50086c`.
Actual shell: `/nix/store/sbifihfd0fpcdpxsx52i2lwv3iy3jw6h-sleepy-shell-0.2.0`.

Original qcow2 remained read-only backing for a separate qcow2 overlay. A 2GiB diagnostic VM logged in using the existing real password. No installed service, QML, PAM, or user configuration was patched. Initial log extraction booted the installer ISO and mounted root `ro,rescue=nologreplay,nosuid,nodev,noexec`.

Reproduction (diagnostic only): attach bounded `timeout 20 strace -f -e trace=write,read -s 1000 -p <actual shell PID>`; SIGKILL only the actual `sleepy-session.service` main process; wait until its new PID is active; run as installed user `sleepy-shell-ipc --any-display call sleepy lock`. Five seconds later issue that same command once as a manual control. Keep raw tracing private; the sanitized fields below are sufficient.

| Actual ordered event | Relevant data |
| --- | --- |
| Last old-daemon event observed by shell | generation 570 |
| New daemon becomes active | guest monotonic79.87s |
| First real IPC command exits | exit0 |
| Shell writes lock request | expectedGeneration570 |
| Daemon rejects first request | generation578; status failed; diagnostic `request.generation-stale` |
| Shell receives new fullSnapshot | generation579 |
| Later manual control | guest monotonic84.91s; expectedGeneration598 |
| Native lock confirmation in event stream | secure true; generation599 |
| Manual control completion | status succeeded; generation600 |

Conclusion: a real lock command was sent with the previous daemon's generation before the reconnect snapshot arrived. The active void shell IPC discarded the command error. The subsequent unchanged native locker successfully locked; this failure was unrelated to password or compositor focus.

Separate raw diagnostic files are local only. No password text or native authentication traffic was traced. Both diagnostic QEMU instances are stopped. The corrective Qt regression and later exact-package VM validation are separate evidence.

Correction: desktop `0a72d23ad6ed4a4c384020e7e5c0999df7c23970`, tracked in
[sleepy-desktop PR10](https://github.com/sleepylinux/sleepy-desktop/pull/10).
Only implicit lock intent may wait for a ready snapshot for up to 10 seconds
and retry one explicit stale-generation rejection. Explicit UUIDs retain their
original correlation API. Transport failure, timeout or second stale rejection
is terminal; other mutations are never replayed. The root pins it at
`7c75fa825a747420fc453c7be0e8f9bab18c59cd`.

Root re-ran 499 Qt checks (one existing skip), 14 focused cases through the full
suite, and load/IPC/service-boundary/direct-integration/parity fixtures. The Nix
packaged QML check and public module build also passed. Corrected fresh-image VM
acceptance is pending separately; these regressions do not relabel the failed VM.
