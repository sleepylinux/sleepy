# Reviewed downstream fixes

Sleepy keeps component inputs pinned to the revisions recorded in
`components/desktop-m1.json`. These small downstream patches fix issues found
by installation and sustained desktop acceptance. They are applied by the root
overlay without editing or publishing the upstream repositories.

- `hyprland-session-lock-vt-focus.patch`: send keyboard leave to the focused
  client before removing the seat's keyboard capability. During a VT switch,
  keyboards disappear and return. Qt 6.11.1 clears its active window when the
  keyboard is destroyed but retains its display focus cache without leave;
  entering the same surface then fails to reactivate input. Preserve the
  compositor focus target for the normal enter when the keyboard returns.
  This does not change authentication or lock ownership. Hyprland remains on
  the locked Nixpkgs version; the usability contract checks patch integration
  separately from the external Sleepy component manifest.

- `session-bounded-audio-refresh.patch`: replace self-observing `pw-mon` triggers
  with coalesced 500 ms audio refreshes. Read-only PipeWire clients generate
  monitor output themselves; using every line as a refresh trigger creates a
  feedback loop. Embedded Rust tests cover the bounded cadence and cancellation.

- `desktop-bounded-nmcli.patch`: distinguish network reads from mutations and
  destroy completed dynamic command objects. A successful radio-status read
  previously scheduled another refresh, creating an unlimited loop whose
  finished process objects remained owned by the QML singleton.

- `locker-supported-unlock.patch`: clear the bound lock request after successful
  native authentication and the existing secure/hold checks. The private C++
  `unlock` slot is not available to QML; calling it left an authenticated user
  locked behind a hidden password card. The writable property binding performs
  the supported protocol transition. Restore native password focus when the
  lock window becomes active. Clicking the password field
  focuses input instead of submitting an empty password. Real Qt window tests
  cover activation and mouse focus while preserving authentication guards.
  Item focus alone does not repair a missing platform window activation;
  the compositor patch addresses the separately reproduced VT transition.

`checks/component-contract.nix` explicitly records the allowed patches, checks
the original source and package provenance, and includes each patch's SHA-256
in the generated component report. Unlisted components remain direct aliases.
When updating component pins, review whether each patch is still necessary;
remove it only after the corresponding upstream fix and regression checks pass.
