# Candidate 7231: DPMS wake diagnostic

Separate follow-up on the same disposable installed disk; this does not convert
`candidate7231-partial-result.json` into a passing acceptance run.

Image source: `7231d4b2bf320440365b0f51a323f3466c724dd1`.
ISO SHA-256: `8237aeac149bc6d281a13b55bd01da1fa5cc998768525efb3bd52048af1a8608`.
Normal graphical login used the installed user's password, without PAM changes.

The verbatim `candidate7231-wake-report.txt` records:

- At 01:19:59 UTC, tty2 and monitor `dpmsStatus: true`.
- After 330 seconds on tty2, `dpmsStatus: false`.
- Returning to tty1 alone leaves DPMS off.
- A QMP relative-pointer x=10 event with the USB tablet attached also leaves it off.

`candidate7231-wake-before-input.png` preserves the stale framebuffer after the
VT return. After that report completed, an ordinary QMP Shift press/release
restored the visible native password UI, shown in
`candidate7231-wake-after-shift.png`. The latter was inspected before copying:
its password field is empty. The report does not contain a subsequent DPMS
query, so the post-Shift evidence is the actual visible screen, not a fabricated
`dpmsStatus` record. No secret or credential file is included.

The runner now sends ordinary Shift after returning to tty1 for Software and
lock checks. It retains the real password-visible assertion, authentication,
and all existing deadlines. No forced `hyprctl dpms on`, idle-policy change,
or authentication bypass was introduced. This diagnostic demonstrates normal
wake behavior; the complete patched runner still needs its own successful run.
