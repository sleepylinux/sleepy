# Installed rollback dispatch failure and lock correction evidence

Image d16f473f5ddf778dec87447dd2562c9bbf58222c; candidate and clean runner
a3837f1b75a430561b85647bd84f3df91858bb0c. KVM, 6 GiB, signed local cache.
The result stays **failed** (36 recorded gates), not complete update acceptance.

Actual visible TUI installation, disk-only password login, daily defaults,
PNG save/view/clipboard and both first/candidate lock cycles passed. The candidate
boot exercised the corrected desktop15b8dab/sessionca37deb: shell/session restart,
native password unlock, layout/VT/input wake all passed. Candidate preparation
preserved the live system and installed configuration; wrong hash, invalid config
and real builder SIGTERM gates passed. Re-preparing the same candidate released
only its temporary GC root; saved rebuild retained the candidate source/output.

`candidate-guest-report.txt` then records the rollback failure: nixos-rebuild
tried auto-reexec through `/etc/nixos#sleepy`, but the installed flake exports
`installed`. No third boot was reached. Commit8624092 uses the installed tool
with `--no-reexec --flake /etc/nixos#installed`; its pinned upstream dispatch
regression also requires rollback with a missing or malformed saved flake,
without source evaluation/build. Fresh installed-VM verification of that fix
is pending. Never turn this failure into a success record.

The raw installer safety transcript is losslessly gzip-compressed.
The exact ISO checksum and component pins are in image.json. Passwords, virtual
disks and firmware variables are excluded; copied evidence was scanned against
the temporary test credential without printing it.
