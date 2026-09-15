# Resume frame scheduling after session activation

This downstream patch is restricted to Hyprland **0.56.2**. It is not an upstream
accepted fix and does not change session-lock authentication or DPMS policy.

A lock surface may map and commit while the graphical session is inactive.
`CMonitor::scheduleFrame` rejects those frame requests. On activation, the
compositor queues monitor-rule reload, but that reload runs from
`render.preChecks`: it cannot itself start the first frame. Aquamarine may restore
the previous scanout buffer. The patch damages monitors and explicitly requests a
frame after the compositor acknowledges session activation. The existing
scheduling guard continues to exclude disabled outputs.

`check.nix` compiles the exact pinned production activation callback and monitor
scheduling guard with recording collaborators. The unpatched callback must fail
specifically because activation never schedules the dropped frame. The patched
callback must schedule enabled outputs while inactive and disabled outputs remain
unscheduled. This check does not establish DRM, locker rendering, or PAM behavior.

Required integration comparison: on the same disposable installed disk, create a
native lock while the graphical VT is inactive, return to that VT, and verify a
visible password prompt followed by real password authentication. Also retain the
normal active-lock VT roundtrip and shell-crash/DPMS-wake scenarios. Record the
exact compositor package used.

Runtime comparison passed on the existing disposable installed disk using
`/nix/store/vab6yfkk554x20wrmv2pafax1c23mvxa-hyprland-0.56.2`, verified through the
running compositor's `/proc` executable. After shell and session daemon SIGKILL
on VT2, 220 seconds of inactivity created the native lock. Returning to VT1 with
ordinary Shift showed the password prompt without a damage command or DPMS rescue;
real password authentication succeeded. Active-lock shell SIGKILL, DPMS off/input
wake, and another locked VT roundtrip also passed. This is runtime package A/B
proof on the existing disk, not fresh installation acceptance for a rebuilt ISO.
The source report is `work/debug-usability/patched-hyprland-actual-ab.json`;
compact published evidence belongs in the acceptance documentation.

On a Hyprland upgrade, remove or rebase this patch only after reviewing activation,
monitor-rule reload and frame scheduling. If upstream already schedules activation
frames, the red check deliberately fails: remove the downstream patch and retain
the real inactive-lock integration regression before accepting the upgrade.
