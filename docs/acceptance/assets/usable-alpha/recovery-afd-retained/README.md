# Retained-disk recovery investigation

The source229 image completed a public-network-only TUI installation and real
password desktop login. Its original `result.json` remains interrupted: the VM
firmware initially selected the broken disk instead of the recovery image.
The original install evidence is in `../recovery-229-public/`.

`result.json` here records the successful continuation on that same installed
and intentionally damaged disk. Recovery image was **afd713c5098900061209a746742b5525acdbfbe8**;
runner was **fc56758cf7043306f477940db1ac2eeee8e4cc9c**. No guest runtime patches
were used. `resume-diagnostic.py` is the exact local orchestration, retained for
provenance; its disposable input disk and private credential were removed after
verification. Use the regular fresh VM command to reproduce the final gate.

The recovery ISO was offline. Actual mounted-ESP install/recovery requests were
rejected, both full partition hashes and GPT matched after read-only inspection
and default Back, and the visible TUI restored the deleted boot entries. After
shutdown and ISO removal, the same user authenticated offline. The system
profile, user proof file and saved Nix configuration matched; desktop, keyring,
PNG/settings persistence and clean shutdown passed.

The other result files preserve failed/interrupted investigation attempts:

- `vm-r1-recovery-resume`: missing lsblk tree topology rejected the valid layout.
- `vm-r1-recovery-fixed`: ambiguous OCR matched the disk prompt as inspection.
- `vm-r1-recovery-ready`: actual kernel rejected standalone `nologreplay`.
- `vm-r2` / `vm-r3`: fresh installations stopped while those defects were being
  isolated; these are not completed installations or recovery passes.

The three diagnostic helper failures have an empty Python KeyboardInterrupt
string in their original JSON. They were stopped after the recorded failure was
observed; their original failed status is preserved. The final success does not
turn any of those runs green. The fresh combined gate is recorded separately.
