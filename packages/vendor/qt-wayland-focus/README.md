# Qt Wayland keyboard-capability focus reset

Qt 6.11.1 loses window activation when a focused keyboard disappears and is
recreated for the same still-live surface. In Hyprland a VT switch can remove
all keyboards, which triggers this path for the native session locker.

The upstream `Keyboard` destructor clears global Qt focus directly but leaves
`QWaylandDisplay::mLastKeyboardFocus` unchanged. A subsequent `wl_keyboard.enter`
for the same surface hits the display's equality shortcut, leaving the Qt window
inactive. The one-line downstream patch uses the existing `handleFocusLost()`
path, which clears both keyboard focus and display activation tracking. It does
not alter lock state, PAM, keyboard mappings, input text or compositor policy.
This is a local fix, not a claim of upstream acceptance.

Sources pinned to the exact Qt release:

- [Keyboard lifecycle and capability handling](https://github.com/qt/qtbase/blob/v6.11.1/src/plugins/platforms/wayland/qwaylandinputdevice.cpp)
- [Display focus bookkeeping](https://github.com/qt/qtbase/blob/v6.11.1/src/plugins/platforms/wayland/qwaylanddisplay.cpp)
- [Existing mock-compositor client tests](https://github.com/qt/qtbase/blob/v6.11.1/tests/auto/wayland/client/tst_client.cpp)

`default.nix` patches the original nixpkgs qtbase derivation, builds its
WaylandClient target and installs only `libQt6WaylandClient.so*`. Internal
Core/Gui build dependencies are not installed. The replacement retains the
original library's runtime search path and uses the installed exact-version Qt
Core/Gui and plugins. It must be selected only for the native locker process;
changing `QT_PLUGIN_PATH` alone does not replace this shared library. No global
Qt override or system environment variable is needed. The version assertion
requires a fresh audit on Qt upgrades.

`test-client.nix` adds a regression to Qt's own mock-compositor client suite and
builds the test against the unmodified installed Qt. `check.nix` checks normal
focus/key events, requires the old library to fail the capability-remove/readd
case, and runs the same executable with the patched library. It exercises real
Qt/Wayland objects without Hyprland, a VM, PAM or credentials. Actual installed
locker VT return and native authentication remain a separate acceptance gate.
