# Desktop Milestone 4: installer and hardware validation roadmap

M4 may begin only after the M3 desktop is published, its rollback path is
verified, and the installer threat model has an independent security review.
M3 contains contracts and fake providers only; it performs no disk, account,
network, firmware, or physical-device mutation.

## Installer stages and threat gates

1. **Read-only discovery.** Enumerate disks, partitions, firmware mode,
   networking, and the proposed machine profile. Reject ambiguous device IDs,
   mounted targets, unknown manifest versions, and insufficient capacity.
2. **Explicit plan.** Render a versioned installation manifest containing
   exact stable device identifiers, destructive operations, sizes, encryption
   choices, profile revisions, and rollback limits. No command is executable
   from free-form text.
3. **Human confirmation.** Require a fresh confirmation bound to the manifest
   digest and device identity. Any rescan difference invalidates confirmation.
4. **Staged execution.** Use fixed argv or typed APIs, bounded subprocesses,
   durable journals, power-loss checkpoints, and verified readback after every
   mutation. Never continue after an identity or generation mismatch.
5. **First boot and rollback.** Advance the SDK first-boot state machine only
   after confirmed system generations. Preserve recovery media instructions
   and refuse rollback when its declared safety preconditions are not met.

Real disk tests require a disposable virtual block device until the hardware
lab gates below are approved. Production disks, user accounts, and live
network configuration are never targets of CI acceptance.

## Hardware-lab matrix

The initial matrix covers UEFI and legacy-boot fixtures; SATA, NVMe and USB
storage; Intel, AMD and ARM64 CPU classes; integrated and discrete GPUs;
single and dual displays; Wi-Fi, Ethernet and offline states; Bluetooth;
battery and desktop power; PipeWire audio; brightness devices; suspend/resume;
and unavailable, unsupported, permission-denied, timeout, parse and generic
error capability states. Each row identifies whether it is simulated,
recorded-fixture replay, disposable VM hardware, or explicitly approved
physical hardware.

Physical execution needs a named operator, isolated device inventory, recovery
procedure, data-loss acknowledgement, and a reviewed test revision. Hardware
quirks remain declarative provider data; ad-hoc privileged scripts are out of
scope.

## Report format and rollout

Every lab report records schema version, report ID, immutable source revisions,
machine-profile digest, typed device identifiers, capability snapshot,
fixture provenance, commands or APIs invoked, bounded timestamps, results,
diagnostics, artifact hashes, operator approval, and whether destructive or
physical actions occurred.

Rollout progresses through contract fixtures, disposable QEMU block devices,
reproducible lab machines, opt-in canary installations, and finally a guarded
stable channel. Promotion requires zero unexplained data-loss events, complete
recovery evidence, architecture-specific evaluation, and an independently
reviewed rollback decision. Any identity mismatch, journal ambiguity, or
unreconciled first-boot state stops promotion.
