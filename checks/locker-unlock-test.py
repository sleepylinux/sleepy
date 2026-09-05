#!/usr/bin/env python3
"""Check the pinned real QML lock API and production handler guards, without locking."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
runner = sys.argv[2]
match = re.search(r'                onAuthenticated: \{\n(.*?)^                }', source, re.M | re.S)
if match is None:
    raise SystemExit('Could not locate the production authenticated handler.')
handler = match.group(1)
# The real lock remains false throughout. A separate state fixture exercises the
# production handler's native-PAM signal boundary and suspend-hold truth table.
qml = '''import QtQuick
import Quickshell
import Quickshell.Wayland
Scope {
    id: root
    property bool lockRequested: false
    WlSessionLock { id: realLock; locked: false }
    QtObject {
        id: sessionLock
        property bool secure: false
        property bool locked: root.lockRequested
    }
    QtObject { id: endpoint; property bool unlockAllowed: false }
    function authenticated() {
HANDLER
    }
    function require(condition, message) {
        if (!condition)
            throw new Error(message)
    }
    Timer {
        interval: 1
        running: true
        onTriggered: {
            try {
                require(typeof realLock.locked === "boolean", "Real lock lacks its public locked property")
                require(typeof realLock.unlock === "undefined", "Update the API regression: unlock became public")
                const combinations = [[false, false], [false, true], [true, false], [true, true]]
                for (const state of combinations) {
                    root.lockRequested = true
                    sessionLock.secure = state[0]
                    endpoint.unlockAllowed = state[1]
                    authenticated()
                    const expectedLocked = !(state[0] && state[1])
                    require(root.lockRequested === expectedLocked, "Native authentication must respect secure and suspend-hold guards")
                    require(sessionLock.locked === root.lockRequested, "Lock binding must follow the requested state")
                }
                root.lockRequested = true
                require(sessionLock.locked === true, "Unlock must preserve the binding for a later lock")
                root.lockRequested = false
                require(realLock.locked === false, "API test must never acquire a real lock")
                console.log("SLEEPY_LOCKER_UNLOCK_TEST_PASS")
            } catch (error) {
                console.log("SLEEPY_LOCKER_UNLOCK_TEST_FAIL " + error)
            }
            Qt.quit()
        }
    }
}
'''.replace('HANDLER', handler)
with tempfile.TemporaryDirectory(prefix='sleepy-locker-unlock-test-') as temporary:
    directory = Path(temporary)
    config = directory/'shell.qml'
    config.write_text(qml)
    runtime = directory/'runtime'
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime))
    environment.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run([runner, '-p', str(config)], env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    if result.returncode or 'SLEEPY_LOCKER_UNLOCK_TEST_PASS' not in result.stdout or 'SLEEPY_LOCKER_UNLOCK_TEST_FAIL' in result.stdout:
        raise SystemExit('Locker public API / authenticated-handler regression failed.')
