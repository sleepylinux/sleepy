# Hyprland Sleepy desktop acceptance record

## Current status

**PARTIAL — post-review candidate; current automated and formal VM evidence
must be recorded against the final pinned graph.**
The operator confirmed the preceding visual deployment on 2026-09-02. That
smoke test predates the protected-action and recording fixes and is not evidence
for the current component heads. The disposable recovery VM was subsequently
removed at the operator's request. No exact-pixel parity, rollback drill,
redacted evidence bundle, or downgrade is claimed by this file.

Follow `docs/runbooks/sleepy-vm-hyprland.md`. Replace every `PENDING` only from
fresh evidence produced by the exact immutable public graph. Do not paste raw
journals, credentials, SSIDs, notification text, document paths, device names,
or other user data.

## Immutable candidate

| Field | Evidence |
| --- | --- |
| Root commit | this file's containing review commit; resolve with `git rev-parse HEAD` |
| `flake.lock` SHA-256 | `543dad46f74c043541a7bf9e1fa019e658effa6dbcf6698e4d94c3915adbef39` |
| `sleepy-sdk` revision | `1ee5b424887eb6f7acfe3b931b37a2c610ff6498` |
| `sleepy-session` revision | `125efe94e4ef9b22dea1369c4bbb11d4cad80237` |
| `sleepy-artwork` revision | `175314b9c236c1b412e8e1ebc54bbe3937b0c90d` |
| `sleepy-desktop` revision | `57f8e72ad7eaed62c5e8b6061ceefbb4dcc26697` |
| NixOS toplevel | PENDING: rebuild final pinned graph |
| `nix flake check --print-build-logs` | PENDING: current graph; preceding log hashes do not apply |
| production VM check result | PENDING: current graph |
| desktop QML/full-shell/locker result | PENDING: current graph |
| root source-contract result | PENDING: current graph |
| isolated source after evaluation/build | PENDING: current graph |

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
| network through fixed-argv `nmcli`; audio through native PipeWire | PENDING | PENDING |
| absent battery/backlight/Bluetooth degrade independently | PENDING | PENDING |
| daemon restart recovery | PENDING | PENDING |
| shell restart recovery | PENDING | PENDING |
| PAM failure/empty input and lock crash cases remain secure | PENDING | PENDING |
| suspend waits for secure lock and resumes securely | PENDING | PENDING |
| hibernate waits for secure lock and follows the guarded sleep lifecycle | PENDING | PENDING |
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

- Integration decision: operator approved merging the tested implementation on
  2026-09-04, explicitly accepting that full 1:1 Caelestia parity is unconfirmed.
  This is not completion of the manual acceptance matrix above.
- Open failures/deviations: `sleepy-desktop/tests/full-parity-contract.sh`
  currently exits 1: the parity manifest is still v1 and retains deviations;
  a complete verified reference comparison is absent. This strict parity gate
  is separate from the standard Nix checks. Real GPU recording remains unverified.
- Rollback bundle retention decision: PENDING
- Raw evidence deletion confirmed: PENDING
- Reviewer approval: PENDING
