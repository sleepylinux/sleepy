#!/usr/bin/env python3
"""Exercise production Nmcli QML with in-memory processes; never invoke nmcli."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
runner = sys.argv[2]
functions = []
for name in ("executeCommand", "isMutationCommand"):
    match = re.search(r"^    function " + name + r"\([^\n]*\).*?^    }", source, re.M | re.S)
    if not match:
        raise SystemExit(f"Missing production function: {name}")
    functions.append(match.group())
exit_handler = re.search(r"^        onExited: code => \{.*?^        }", source, re.M | re.S)
if not exit_handler:
    raise SystemExit("Missing production exit handler")
exit_function = exit_handler.group().replace("onExited: code =>", "function complete(code)", 1)

qml = '''import QtQuick
import QtTest
TestCase {
    id: root
    name: "NmcliLifecycle"
    property list<var> activeProcesses: []
    property int created: 0
    property int destroyed: 0
    property int executed: 0
    property int callbacks: 0
    property int refreshes: 0
    property bool allowRefresh: false
    property bool passwordHandled: false
    property bool alreadyCalled: false
    property string lastError: ""
    property var pendingConnection: null
    function isConnectionCommand(args) { return false }
    function detectPasswordRequired(error) { return false }
    function handlePasswordRequired(proc, error, output, code) { return root.passwordHandled }
    function refresh() {
        verify(root.allowRefresh, "Read commands must not schedule a refresh")
        root.refreshes++
    }
    readonly property Component commandProc: Component {
        QtObject {
            id: proc
            property list<string> cmdArgs: []
            property var callback
            property string stdinPayload
            property bool callbackCalled: root.alreadyCalled
            property int exitCode: 0
            readonly property QtObject stdoutCollector: QtObject { property string text: "enabled" }
            readonly property QtObject stderrCollector: QtObject { property string text: "" }
            signal processFinished
            Component.onCompleted: root.created++
            Component.onDestruction: root.destroyed++
            function exec(args) {
                root.executed++
                complete(0)
            }
            EXIT_FUNCTION
        }
    }
    function test_classification_data() {
        return [
            {tag:"radio query", args:["nmcli", "radio", "wifi"], mutation:false},
            {tag:"all radios query", args:["nmcli", "radio", "all"], mutation:false},
            {tag:"wifi enable", args:["nmcli", "radio", "wifi", "on"], mutation:true},
            {tag:"wifi disable", args:["nmcli", "radio", "wifi", "off"], mutation:true},
            {tag:"reserved connection name", args:["nmcli", "connection", "show", "radio"], mutation:false},
            {tag:"reserved device name", args:["nmcli", "device", "show", "connect"], mutation:false},
            {tag:"filtered read", args:["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], mutation:false},
            {tag:"connection enable", args:["nmcli", "--ask", "connection", "up", "Home"], mutation:true},
            {tag:"device disconnect", args:["/nix/store/test/bin/nmcli", "device", "disconnect", "eth0"], mutation:true},
            {tag:"wifi connect", args:["nmcli", "device", "wifi", "connect", "Home"], mutation:true},
            {tag:"connection modify", args:["nmcli", "connection", "modify", "Home", "connection.autoconnect", "yes"], mutation:true},
            {tag:"empty", args:[], mutation:false}
        ]
    }
    function test_classification(data) {
        compare(root.isMutationCommand(data.args), data.mutation)
    }
    function test_completed_process_objects_are_destroyed() {
        for (let batch = 0; batch < 10; batch++) {
            for (let index = 0; index < 50; index++)
                root.executeCommand(["radio", "wifi"], function(result) {
                    compare(result.output, "enabled")
                    root.callbacks++
                }, "")
            tryCompare(root, "executed", (batch + 1) * 50)
            tryCompare(root, "destroyed", (batch + 1) * 50)
            compare(root.activeProcesses.length, 0)
            compare(root.created, root.destroyed)
            compare(root.callbacks, root.executed)
        }
    }
    function test_throwing_callback_still_destroys_process() {
        const previous = root.destroyed
        ignoreWarning(/.*intentional callback failure.*/)
        root.executeCommand(["radio", "wifi"], function() {
            throw new Error("intentional callback failure")
        }, "")
        tryCompare(root, "destroyed", previous + 1)
        compare(root.activeProcesses.length, 0)
    }
    function test_early_return_paths_destroy_process() {
        for (const mode of ["password", "already-called", "no-callback"]) {
            const previous = root.destroyed
            root.passwordHandled = mode === "password"
            root.alreadyCalled = mode === "already-called"
            root.executeCommand(["radio", "wifi"], mode === "no-callback" ? null : function() {
                fail("Early return must not invoke callback")
            }, "")
            tryCompare(root, "destroyed", previous + 1)
            compare(root.activeProcesses.length, 0)
        }
        root.passwordHandled = false
        root.alreadyCalled = false
    }
    function test_mutation_refreshes_once_and_destroys_process() {
        const previousDestroyed = root.destroyed
        const previousCallbacks = root.callbacks
        const previousRefreshes = root.refreshes
        root.allowRefresh = true
        root.executeCommand(["radio", "wifi", "on"], function(result) {
            compare(result.output, "enabled")
            root.callbacks++
        }, "")
        tryCompare(root, "destroyed", previousDestroyed + 1)
        tryCompare(root, "refreshes", previousRefreshes + 1)
        wait(20)
        compare(root.refreshes, previousRefreshes + 1)
        compare(root.callbacks, previousCallbacks + 1)
        compare(root.activeProcesses.length, 0)
        root.allowRefresh = false
    }
'''.replace("EXIT_FUNCTION", exit_function) + "\n".join(functions) + "\n}\n"

with tempfile.TemporaryDirectory(prefix="sleepy-nmcli-test-") as temp:
    test = Path(temp) / "tst_nmcli.qml"
    test.write_text(qml)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
    env.pop("QT_QPA_PLATFORMTHEME", None)
    subprocess.run([runner, "-input", str(test)], env=env, check=True, timeout=60)
