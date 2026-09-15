{pkgs}: let
  testClient = import ./test-client.nix {inherit pkgs;};
  patched = import ./. {inherit pkgs;};
in
  pkgs.runCommand "qt-wayland-keyboard-capability-focus" {
    nativeBuildInputs = [pkgs.gnugrep];
  } ''
    mkdir -p "$out"
    export QT_QPA_PLATFORM=wayland
    unset LD_PRELOAD LD_LIBRARY_PATH
    # A normal enter/leave and key-event cycle must work on unpatched Qt.
    ${testClient}/bin/tst_client activeWindowFollowsKeyboardFocus events > "$out/baseline.log" 2>&1
    # The reproducer must fail specifically on focus restoration, not setup.
    if ${testClient}/bin/tst_client keyboardCapabilityRestoresFocus > "$out/red.log" 2>&1; then
      echo 'The Qt regression no longer reproduces; re-audit/remove the patch.' >&2
      exit 1
    fi
    grep -F 'keyboardCapabilityRestoresFocus() Compared QObject pointers are not the same' "$out/red.log"
    grep -F 'Actual   (QGuiApplication::focusWindow()): <null>' "$out/red.log"
    grep -F 'Totals: 2 passed, 1 failed' "$out/red.log"
    LD_LIBRARY_PATH=${patched}/lib ${testClient}/bin/tst_client \
      activeWindowFollowsKeyboardFocus keyboardCapabilityRestoresFocus events > "$out/green.log" 2>&1
    grep -F 'Totals: 5 passed, 0 failed' "$out/green.log"
  ''
