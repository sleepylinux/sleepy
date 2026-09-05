#!/usr/bin/env python3
"""Route real Qt window keyboard/mouse events to the packaged native secure prompt."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

locker = Path(sys.argv[1])
runner = sys.argv[2]
source = (locker/'share/sleepy-locker/LockRoot.qml').read_text()
match = re.search(r'^                Window.onActiveChanged: \{.*?(?=^                Component.onCompleted:)', source, re.M | re.S)
focus_handler = match.group() if match else ''
# Retain the old handler on an unpatched package so this is a behavioral red test.
click = re.search(r'^                    on(?:Focus|Authenticate)Requested:.*$', source, re.M)
if not click:
    raise SystemExit('Missing production password-field handler')
qml = '''import QtQuick
import QtTest
import Sleepy.Locker.Native
Item {
Window {
    id: lockWindow
    visible: true
    width: 1000
    height: 700
    property Window otherWindow: Window {
        visible: false
        width: 100
        height: 100
        transientParent: null
    }
    SecurePrompt {
        id: prompt
        anchors.fill: parent
        focus: true
        FOCUS_HANDLER
        SleepyLockView {
            id: view
            anchors.fill: parent
            inputLength: prompt.inputLength
            authState: prompt.authState
            CLICK_HANDLER
        }
    }
    Item { id: competingItem; width: 1; height: 1 }
    TestCase {
        name: "LockerWindowFocus"
        when: windowShown
        function init() {
            lockWindow.otherWindow.hide()
            lockWindow.requestActivate()
            tryVerify(() => lockWindow.active)
            prompt.forceActiveFocus()
            tryVerify(() => prompt.activeFocus)
            keyClick(Qt.Key_Escape)
            compare(prompt.inputLength, 0)
        }
        function test_window_reactivation_restores_native_keyboard_focus() {
            lockWindow.otherWindow.show()
            lockWindow.otherWindow.requestActivate()
            tryVerify(() => lockWindow.otherWindow.active)
            compare(lockWindow.visible, true)
            // Simulate the lost native item focus while the secure surface is
            // still mapped, as seen when returning from a different VT.
            competingItem.forceActiveFocus()
            compare(prompt.focus, false)
            lockWindow.requestActivate()
            tryVerify(() => lockWindow.active)
            tryVerify(() => prompt.activeFocus)
            keyClick(Qt.Key_A)
            compare(prompt.inputLength, 1)
            keyClick(Qt.Key_Escape)
            compare(prompt.inputLength, 0)
        }
        function test_password_field_click_focuses_without_authentication() {
            wait(800) // Let the production view's intro transform finish.
            competingItem.forceActiveFocus()
            compare(prompt.activeFocus, false)
            const input = findChild(view, "sleepyPasswordFocusTarget")
            verify(input !== null)
            const previousState = prompt.authState
            mouseClick(input, input.width / 2, input.height / 2)
            tryVerify(() => prompt.activeFocus)
            compare(prompt.authState, previousState)
            keyClick(Qt.Key_B)
            compare(prompt.inputLength, 1)
            keyClick(Qt.Key_Escape)
        }
    }
}
}
'''.replace('FOCUS_HANDLER', focus_handler).replace('CLICK_HANDLER', click.group())
with tempfile.TemporaryDirectory(prefix='sleepy-locker-focus-test-') as temporary:
    directory = Path(temporary)
    (directory/'tst_focus.qml').write_text(qml)
    view = (locker/'share/sleepy-locker/SleepyLockView.qml').read_text()
    # Name the actual production password hit target for mouse routing; no
    # behavioral substitution or direct call to its click handler is made.
    view = view.replace('MouseArea {', 'MouseArea {\n                        objectName: "sleepyPasswordFocusTarget"', 1)
    (directory/'SleepyLockView.qml').write_text(view)
    runtime = directory/'runtime'
    runtime.mkdir(mode=0o700)
    imports = str(locker/'lib/qt6/qml') + os.pathsep + os.environ.get('QML_IMPORT_PATH', '')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
               QML_IMPORT_PATH=imports, QML2_IMPORT_PATH=imports)
    subprocess.run([runner, '-input', str(directory)], env=env, check=True, timeout=40)
