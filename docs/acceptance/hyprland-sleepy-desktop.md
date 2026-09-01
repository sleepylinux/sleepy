# Hyprland Sleepy desktop acceptance record

## Current status

**PENDING — template only.** No real `Sleepy` VM switch, rollback drill,
interactive login, framebuffer inspection, downgrade, or production pin/lock
verification is claimed by this file.

Follow `docs/runbooks/sleepy-vm-hyprland.md`. Replace every `PENDING` only from
fresh evidence produced by the exact immutable public graph. Do not paste raw
journals, credentials, SSIDs, notification text, document paths, device names,
or other user data.

## Immutable candidate

| Field | Evidence |
| --- | --- |
| Root commit | PENDING |
| `flake.lock` SHA-256 | PENDING |
| `sleepy-sdk` revision | PENDING |
| `sleepy-session` revision | PENDING |
| `sleepy-artwork` revision | PENDING |
| `sleepy-desktop` revision | PENDING |
| NixOS toplevel | PENDING |
| `nix flake check --no-write-lock-file -L` | PENDING |
| production VM check derivation/result | PENDING |
| clean checkout after evaluation/build | PENDING |

Local candidate commits are not production pins. Record a revision here only
after the public input and generated lock node resolve to the same reviewed
commit.

The derivation's automated ReGreet gate uses a credential-free test-only PAM
stack. It may support the greeter/UWSM plumbing row, but it is not evidence for
real-password success, empty/incorrect-password rejection, or the manual
bootloader downgrade rows below.

## Rollback bundle and drill

| Field | Evidence |
| --- | --- |
| Protected domain name/UUID | PENDING |
| Captured offline state | PENDING |
| Prior system path/generation | PENDING |
| Inactive XML hash | PENDING |
| Original disk target/format/backing-chain hash | PENDING |
| Flattened disk copy/check hash | PENDING |
| NVRAM copy hash | PENDING |
| Bundle manifest/checksum result | PENDING |
| Temporary verification domain UUID | PENDING |
| Restored system path | PENDING |
| Restored greetd/ReGreet lifecycle | PENDING |
| Temporary domain identity-checked cleanup | PENDING |
| Protected `Sleepy` domain remained off | PENDING |

Bundle location is sensitive host metadata and must not be committed. Record a
stable evidence-set identifier and artifact hashes, not host paths.

## Real VM functional matrix

| Gate | Result | Redacted evidence hash/reference |
| --- | --- | --- |
| ReGreet offers UWSM Hyprland; no autologin | PENDING | PENDING |
| Hyprland IPC live; no Niri process/unit/config | PENDING | PENDING |
| daemon ready before shell; locker independently supervised | PENDING | PENDING |
| zero failed system/user units and no restart loop | PENDING | PENDING |
| first desktop frame is complete schema-v3 snapshot | PENDING | PENDING |
| launcher and keyboard navigation | PENDING | PENDING |
| workspaces/window actions/special workspace | PENDING | PENDING |
| notifications, dashboard, sidebar, OSD | PENDING | PENDING |
| theme, wallpaper, opaque and reduced-motion modes | PENDING | PENDING |
| network and audio controls through Sleepy IPC | PENDING | PENDING |
| absent battery/backlight/Bluetooth degrade independently | PENDING | PENDING |
| daemon restart recovery | PENDING | PENDING |
| shell restart recovery | PENDING | PENDING |
| PAM failure/empty input and lock crash cases remain secure | PENDING | PENDING |
| suspend waits for secure lock and resumes securely | PENDING | PENDING |
| logout returns to ReGreet without orphan processes | PENDING | PENDING |
| GTK file chooser portal | PENDING | PENDING |
| Hyprland/PipeWire screencast portal | PENDING | PENDING |

## Visual evidence

Every retained file must be a reviewed, redacted PNG with mode 0600 beneath a
mode-0700 evidence directory. Record SHA-256, reviewer, and deletion date.

| View | SHA-256 | Reviewer | Deletion date | Inspection result |
| --- | --- | --- | --- | --- |
| ReGreet | PENDING | PENDING | PENDING | PENDING |
| unlocked desktop | PENDING | PENDING | PENDING | PENDING |
| launcher | PENDING | PENDING | PENDING | PENDING |
| dashboard/sidebar | PENDING | PENDING | PENDING | PENDING |
| secure lock screen | PENDING | PENDING | PENDING | PENDING |
| post-restart recovery | PENDING | PENDING | PENDING | PENDING |

Raw captures are never committed and are deleted immediately after redaction
review. Redacted artifacts are deleted on the recorded date unless the user
explicitly authorizes retention.

## Downgrade and return

| Gate | Evidence |
| --- | --- |
| prior Niri generation selected from bootloader | PENDING |
| prior generation system path and essential login | PENDING |
| legacy state hashes unchanged | PENDING |
| candidate Hyprland generation reselected | PENDING |
| readiness/full-v3/service checks repeated | PENDING |
| post-return framebuffer inspected | PENDING |

## Final disposition

- Acceptance decision: PENDING
- Open failures/deviations: PENDING
- Rollback bundle retention decision: PENDING
- Raw evidence deletion confirmed: PENDING
- Reviewer approval: PENDING
