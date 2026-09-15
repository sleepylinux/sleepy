# Candidate 7231 partial run — FAILED

This is a failed installed-disk acceptance attempt, not a release acceptance.
The unchanged runner result records 15 completed stages before the visible-lock
check failed: the captured display did not show `Password`. The later real-PAM
unlock, daily application roundtrips and full reboot/recovery sequence are not
proved by this run.

- Image source: `7231d4b2bf320440365b0f51a323f3466c724dd1`.
- ISO SHA-256: `8237aeac149bc6d281a13b55bd01da1fa5cc998768525efb3bd52048af1a8608`.
- Runner: clean `25eb37f77a8875d5ad3c340def8b939b27a25e4b`, KVM,
  `--daily-usability --flatpak-recovery`, Russian keyboard.
- `candidate7231-partial-result.json`: verbatim final failed result. Local ISO
  path, cache endpoint and public signing key are historical provenance.
- `candidate7231-partial-guest-report.txt`: complete compact guest report
  (1,745 bytes). It records real offline Flathub DNS failure at 01:00:16,
  automatic registration after network restoration at 01:05:19–20, and
  `FLATPAK_REAL_FLATHUB_TIMER_RECOVERY_OK`. This was the real public Flathub
  operation, distinct from the controlled-remote systemd regression fixture.
- `candidate7231-installer-flatpak-selected.png`: installer selection visibly
  has Flatpak enabled. It predates the later lavender VT palette change.
- `candidate7231-frozen-frame.png`: the captured frame at the failed visible
  lock check. The Software-stage screenshot was byte-identical (SHA-256 below),
  so only one copy is preserved. Neither frame shows Software or the lock UI.
  `FLATPAK_SOFTWARE_WINDOW_OK` and the corresponding completed-stage label
  establish only the runner's window check, **not visual application proof**.
  The repeated frame is evidence of the capture/display failure, not a diagnosis
  of its cause or proof that the desktop was securely locked.

No disk image, credential file, password/sudo-prompt screenshot or later
interactive diagnostic output is included. No final-candidate VM success is
claimed. The main acceptance record must wait for a complete successful rerun.

## Preserved-file SHA-256

- `candidate7231-partial-result.json`: `aaaacf09b1d6ee8f2f499687553f56b61db5b9c824419498c98ee3079ed42fbc`
- `candidate7231-partial-guest-report.txt`: `8a6af710c2fb17fcad1dd5936a45d9fe60919319a1b72536bd4f2f47cd745441`
- `candidate7231-installer-flatpak-selected.png`: `3b21c6dd373573d08de1bf4ff3c4d15cef9fbe052926f14fa352d415da78a0ee`
- `candidate7231-frozen-frame.png`: `c7d2ae0b3f0a290abdc493e303648b3f2582cda021fbc33c9e510376ce0b3f7b`
