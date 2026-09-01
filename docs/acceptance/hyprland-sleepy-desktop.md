# Hyprland Sleepy desktop acceptance record

## Current status

**PARTIAL — immutable public graph verified; real VM acceptance remains
PENDING.** No real `Sleepy` VM switch, rollback drill, interactive login,
framebuffer inspection, or downgrade is claimed by this file.

Follow `docs/runbooks/sleepy-vm-hyprland.md`. Replace every `PENDING` only from
fresh evidence produced by the exact immutable public graph. Do not paste raw
journals, credentials, SSIDs, notification text, document paths, device names,
or other user data.

## Immutable candidate

| Field | Evidence |
| --- | --- |
| Root commit | this file's containing review commit; resolve with `git rev-parse HEAD` |
| `flake.lock` SHA-256 | `4af281c19ba2e453c7eea49028f6f0d80fe179db0cca10b548228bcbd537c316` |
| `sleepy-sdk` revision | `63b2370a39f47f2b361310c12c0333da0faaee9d` |
| `sleepy-session` revision | `4fee02d6fa221df33b7df03fb1bdadcbb3f8f714` |
| `sleepy-artwork` revision | `175314b9c236c1b412e8e1ebc54bbe3937b0c90d` |
| `sleepy-desktop` revision | `e3d9370c555e99a2fc6fba813f30a90872077c4c` |
| NixOS toplevel | PASS: `/nix/store/mkpbp3qvc0aa105ynmg7ajnd5q10dcfz-nixos-system-sleepy-vm-26.11.20260822.2c423e0` |
| `nix flake check --print-build-logs` | PASS in isolated Docker with KVM; log SHA-256 `2e24200bda9dc7996fe0b2059ca8a3b73ea45f6fc65532aadd2ed5c68dd78274` |
| production VM check result | PASS: `/nix/store/5il94dzrwd62bnkh9bf360q8qmj6j6hp-vm-test-run-sleepy-hyprland-production`; daemon restart and shell reconnect passed in the full log above |
| desktop QML/full-shell/locker result | PASS: `/nix/store/8fmwqrim8ac7cvfqv8a5pxlc7kplg8ld-sleepy-desktop-qml-contracts` |
| root source-contract result | PASS: `/nix/store/zw970f6ia38w40x8fyr2jzkjbbkrv177-sleepy-source-contracts` |
| isolated source after evaluation/build | PASS: the check ran from a fresh `.git`-free source copy; root pin/source contracts and `git diff --check` passed before launch |

Each component was fetched by exact SHA from its public GitHub repository, and
the generated root lock node resolves to that same reviewed revision with a
nonempty `narHash`. SDK, session, and desktop are also advertised by the public
feature branch; artwork remains publicly fetchable as an exact commit object.

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
| notifications, dashboard/sidebar, OSD, plus overlay toast visibility and focus return | PENDING | PENDING |
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
