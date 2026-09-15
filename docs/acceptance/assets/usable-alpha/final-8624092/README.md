# Final installed-disk acceptance — 8624092

**Passed: 44 gates, three real-password installed-disk boots, clean shutdown.**
`result.json` records the executed gates. Image source is
`86240920109f37263c3260ea501c2a15fafa7dd8`; candidate and clean runner are
`d40861dddf01018b4de7bb13a81012de57f23625`. See `image-manifest.json` for the
ISO checksum and resolved component revisions.

The real TUI installed onto a disposable disk, followed by password login,
candidate preparation and password boot, then offline rollback and a third
password boot. Reports cover rejected targets, interrupted installation,
wrong candidate hash, invalid configuration, interrupted preparation, completed
GC-root cleanup, preservation of unrelated roots and saved rebuild source after
candidate boot and rollback. Desktop gates include shell/session crash recovery,
native password locking, layout/VT/DPMS input recovery, screenshots and clipboard,
keyring persistence, first-boot state and bounded 60-second shell idle samples.

8624092 → d408 changes acceptance documentation only: runtime configuration and
component pins are identical. This proves the reviewed-candidate source identity
transition and rollback workflow; it does **not** prove a changed-runtime upgrade.
The separate [88a87c5 upgrade](../upgrade-88a87c5/README.md) subsequently passed
43 gates and three password boots with changed runtime. This run did not select
the Flatpak recovery or boot-repair test modes.

`runner-arguments.json` contains reconstructed reproduction arguments, with the
6 GiB memory setting confirmed by the run owner. Run the pinned runner with a new
output directory and the matching ISO. A signed local cache was used; public
network/source dependencies remain necessary. The explicit test candidate catalog
is not a public release channel or promotion.

## Supplemental native visual inspection

`fastfetch-1280.png` is an unedited 1280×800 QMP capture of actual Fastfetch in
Ghostty: custom ASCII logo and `4.55 GiB / 39.50 GiB (btrfs)` are fully visible
and readable. `visual-applications.png` shows actual Ghostty and Thunar.
These were captured offline in a separate 6 GiB overlay after the passed run's
rollback, using runner `5c218bfa92ea1705a111cf49b5532df1f9571d75` and real password
login. No guest configuration or displayed values were patched. This supplements
the three-boot acceptance; it is not an additional install or update proof.

`visual-provenance.json` records unchanged base-disk stat/NVRAM checks, screenshot
hashes, review and removal of the stopped disposable overlays. The initial visual
navigation attempt opened Thunar Preferences; selecting the actual File Manager
entry resolved that test navigation issue. To reproduce with retained private
base inputs, place the unchanged `visual-reproduce.py` at
`work/visual-final-fastfetch/reproduce.py` under the pinned root workspace; use a
fresh output location and preserve prior evidence. It requires the passed base
disk, NVRAM and private credential, which are intentionally absent here.

Raw installer serial/safety transcripts are losslessly gzip-compressed. Copied
text, uncompressed logs and OCR of selected screenshots were scanned against the
private test credential without printing it. Passwords, disks, firmware variables
and private signing keys are excluded. `evidence-manifest.json` records copied
input paths and hashes; these paths describe the original workspace, not bundled
private inputs.
