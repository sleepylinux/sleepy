# Changed-runtime candidate upgrade — 88a87c5 → d408

**Passed: 43 gates, three real-password installed-disk boots, clean shutdown.**
The original QEMU was confirmed stopped before evidence collection.
Base image: `88a87c599aca03c6612f6cf32ae0d3aa83fd358b`.
Candidate and clean runner: `d40861dddf01018b4de7bb13a81012de57f23625`.
Exact image checksum/pins are in `image-manifest.json`; its historical build-time
pending status is superseded by the passed `result.json` retained here.

The real TUI installed the historical base. The created password opened the base
desktop, then the prepared candidate desktop, then the offline rolled-back base.
The three guest reports preserve completed native lock/password, shell/session
crash recovery, daily screenshots/clipboard, keyring persistence, settings and
60-second idle checks. Candidate tests rejected wrong hashes and invalid
configurations, interrupted preparation safely, preserved the live system during
preparation, released completed attempt GC roots without removing unrelated roots,
and kept the selected source through saved rebuilds. Post-rollback validation
preserved state. This run did not execute installation SIGTERM, Flatpak recovery
or boot repair: these are separate evidence sets.

Unlike the separate 8624092 → d408 documentation-only transition, the exact base
to candidate source diff changes installed runtime: sleepy-system rollback uses
`--no-reexec --flake /etc/nixos#installed`, and Fastfetch uses a compact Disk format
with the actual filesystem. The source also adds immediate installer field
validation using existing backend predicates, and advances the session/desktop
pins (see manifests). Installer validation changes belong to the candidate source;
the installation in this run used the historical base installer, so this run does
not independently exercise those new field retries. Pin changes include dependency
and test updates and are not evidence of new desktop features by themselves.

`runner-arguments.json` gives reconstructed reproduction arguments, not captured
argv. Use the pinned runner, a new disposable output directory and the matching
ISO. A signed local cache and public source/network access were used; the final
rollback boot was offline. The candidate catalog is an explicit local VM fixture,
not a public channel promotion. No runtime patches or fabricated visual values
were injected to make this acceptance pass.

Selected screenshots show the installation options, candidate applications and
offline rollback desktop. Serial and safety logs are losslessly gzip-compressed.
Private credentials, disks, NVRAM and signing keys are excluded. Copied text/raw
logs and OCR of selected PNGs were scanned against the private test credential
without printing it. `evidence-manifest.json` records hashes and original paths.
