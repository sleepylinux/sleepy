# Fresh installed-disk recovery acceptance — 7c75fa8

**Passed: 40 gates, two real-password disk boots, clean shutdown.**
Image 7c75fa825a747420fc453c7be0e8f9bab18c59cd; clean runner
2b7b245605f14cfdef27ad1393226809601e98cc. Exact checksum and pins are
in image-manifest.json; result.json lists the executed gates.

Visible TUI whole-disk installation and actual password login. Invalid target,
offline preflight and real install SIGTERM cleanup passed. Both desktops passed
shell/session crash recovery, native password locking, layout/VT/input wake,
PNG save/view/clipboard, keyring and state persistence. Idle 60-second samples
kept the same shell process with bounded RSS and 0.47/1.81 CPU seconds.

Only task-created disk ESP entries were deleted. The next disk boot genuinely
failed; offline recovery inspection/cancel kept partition hashes unchanged.
The real TUI required exact disk confirmation, repaired boot entries and shut
down. The installed disk booted offline with its real password, original profile,
configuration, personal state and saved PNG. Recovery code/host image settings
are unchanged in the later 8624092 image; this is evidence for 7c75 specifically,
not a claim that a different ISO was booted in this run.

A signed local cache was configured, but its host server was unavailable at
installation start and restored during this run. This is neither a controlled
public-only test nor a fully cache-backed timing benchmark. The recovery/reboot
phases used a disconnected NIC. No guest source patches were injected.

Raw safety/recovery transcripts are losslessly compressed. Temporary passwords,
VM disks and firmware variables are excluded; copied evidence was scanned for
the test credential. The separate candidate-update run on newer d16 remains
failed at rollback dispatch and is recorded in ../rollback-d16f473/.
