# Candidate 7231: graphical input readiness

Follow-up on the same disposable installed disk, image source
`7231d4b2bf320440365b0f51a323f3466c724dd1`; not a complete acceptance run.

The verbatim `candidate7231-keymap-report.txt` records empty compositor keyboard
lists while the audit runs on VT2, still empty after Ctrl+Alt+F1 and a software
`switchxkblayout` request, then actual keyboard devices and the main Russian
keymap after ordinary Shift input. Merely observing the kernel's active tty1
is therefore insufficient to assume compositor keyboard readiness.

The runner emits `LOCK_GRAPHICAL_VT_READY` after checking tty1. On receiving it,
the host sends one normal Shift press/release before the existing bounded
keymap-selection loop completes. The keymap, visible Password, real password
authentication and unlock assertions are unchanged; deadlines are unchanged.
This replaces the later wake immediately before password input, which was too
late to help a keymap loop waiting on inactive compositor input devices.

No compositor policy, input configuration or authentication mechanism changed.
The complete patched workflow still requires a successful VM execution.
