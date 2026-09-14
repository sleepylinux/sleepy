# Read-only doctor acceptance

The `sleepyctl doctor` command and `doctor --json` read the existing session
snapshot, without sending commands or probing hardware. A two-second deadline,
peer UID verification and 1 MiB frame bound protect the read. Output contains
fixed capability names/states, not SSIDs, window titles or provider diagnostics.

## Tested

- Source `8e6e1dbf408e46e4bfb547ce812a9dbed8c5f025`: Nix package
  `/nix/store/m92vdxk75sxrl63pg7ndpxhsh1s78l27-sleepy-session-0.1.0`.
- Nix release build: 483 passing tests, two existing ignored tests; component CI
  [34905891489](https://github.com/sleepylinux/sleepy-session/actions/runs/34905891489)
  passed, including the separate Niri contract gate.
- Fresh boot of the previously installed disposable UEFI VM, without ISO;
  normal password login and sudo. The original installed image remains
  `9bca73c`, not a newly built doctor ISO.
- The exact standalone package closure was streamed into the guest Nix store
  after authentication. No permanent substituter or signature policy changes.
- Human/JSON output as the real desktop user, disconnected virtual NIC,
  stopped daemon returning a bounded error, and recovery after daemon restart.

The integrated session revision `3980ea94547ff42b590e6c96b8ae3b987d7a2dcc`
adds only a deterministic PID-publication test fix after root CI found a race.
Its production `src`, Cargo files and flake match the tested `8e6e1db` exactly.
The new readiness regression and all 52 desktop-services tests pass; startup,
shutdown and child-reaping assertions retain their original bounds.

## Observed limitations

Hyprland and lock report available. Audio and battery providers report `parse`,
Bluetooth reports `timeout`; doctor correctly exits 1 and says the desktop
needs attention. These are existing provider failures requiring follow-up,
not successful hardware checks. Screenshot absence is informational; the
unit tests cover optional hardware absence, but this VM does not certify its
correct classification by real hardware providers. No physical GPU, suspend,
Bluetooth or microphone acceptance is claimed.

Two preliminary transport attempts failed before command verification; a
single bidirectional virtio descriptor and concurrent bounded I/O fixed the
test transport. Another attempt exposed the hardware-status assumption above;
the final report preserves the actual errors instead of treating them as healthy.

## Reproduce

Inside a running Sleepy desktop session:

```sh
nix shell github:sleepylinux/sleepy-session/8e6e1dbf408e46e4bfb547ce812a9dbed8c5f025#sleepy-session -c sleepyctl doctor
nix shell github:sleepylinux/sleepy-session/8e6e1dbf408e46e4bfb547ce812a9dbed8c5f025#sleepy-session -c sleepyctl doctor --json
```

On a disposable VM, disconnect its virtual NIC and repeat. Stop
`sleepy-session.service` with `systemctl --user stop`, check for exit 1 and
`session-unavailable`, then start the service and repeat the report.
Use the [installer runbook](../runbooks/installable-alpha.md) to create the VM;
never apply disruptive verification to a working user session.

Compact raw results are in [assets/doctor](assets/doctor/).
