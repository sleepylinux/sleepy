# Hyprland Sleepy desktop acceptance record

## Current status

**Standard automated checks PASS; full visual/manual acceptance remains PARTIAL.**
On 2026-09-04 the final pinned graph passed the root Nix check, including the
Hyprland production VM and update-safety VM. These isolated VM tests do not
replace the real-hardware and exact-reference acceptance gates below.
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
| Tested integration commit | `7540141debd587d81e45971633419d9c5173e368`; subsequent acceptance-record edits are documentation only |
| `flake.lock` SHA-256 | `543dad46f74c043541a7bf9e1fa019e658effa6dbcf6698e4d94c3915adbef39` |
| `sleepy-sdk` revision | `1ee5b424887eb6f7acfe3b931b37a2c610ff6498` |
| `sleepy-session` revision | `125efe94e4ef9b22dea1369c4bbb11d4cad80237` |
| `sleepy-artwork` revision | `175314b9c236c1b412e8e1ebc54bbe3937b0c90d` |
| `sleepy-desktop` revision | `57f8e72ad7eaed62c5e8b6061ceefbb4dcc26697` |
| NixOS toplevel | `/nix/store/zqwjyskd0pffi61qqr4amblz5nbk38gj-nixos-system-sleepy-vm-26.11.20260822.2c423e0` |
| `nix flake check --print-build-logs` | PASS, x86_64-linux; log SHA-256 `1374ee62d2e69aaa906820d6e23af5b03d3350d89319fa3d104c8def8bd06624` |
| production VM check result | PASS: `/nix/store/xdj3alpzimbk3cpdhzznf9691pqyrbrs-vm-test-run-sleepy-hyprland-production` |
| update-safety VM result | PASS: `/nix/store/97cs0g66nmlyy48s6xqhwh18k2p03frh-vm-test-run-sleepy-niri-to-hyprland-update-safety` |
| desktop QML/full-shell/locker result | PASS: `/nix/store/5bingc8qdmkxxllmy8g2sn1vcz01j0kh-sleepy-desktop-qml-contracts`; primary QML suite 476 passed, 0 failed, 1 skipped |
| root source-contract result | PASS: `/nix/store/rxvfg44p8v6piz6psk3wxhk9fpw3wi96-sleepy-source-contracts` |
| isolated source after evaluation/build | PASS: `/nix/store/8bjzqq4nin6c2g2b8x0rn8jjfvpd92br-sleepy-fresh-clone-source-check` |

The standalone desktop flake also passed all its standard x86_64-linux checks;
its log SHA-256 is `fade2fe17eb2328de7f67fcc3419a04995264d1cb1701cef83f7252dc3f627c9`.
Store paths identify the verified outputs; the temporary local build cache may
be removed at the operator's request and is not a retained rollback bundle.

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
