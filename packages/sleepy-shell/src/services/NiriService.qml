import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var workspaceState: []
    readonly property var workspaces: root.workspaceState

    function acceptWorkspaces(payload: string): void {
        try {
            const parsed = JSON.parse(payload);
            if (!Array.isArray(parsed))
                throw new Error("workspace response is not an array");

            root.workspaceState = parsed.slice().sort((left, right) =>
                Number(left.idx) - Number(right.idx));
        } catch (error) {
            console.warn("Sleepy: ignoring invalid Niri workspace response");
        }
    }

    function focusWorkspace(index: int): void {
        Quickshell.execDetached([
            "niri",
            "msg",
            "action",
            "focus-workspace",
            String(index)
        ]);
    }

    readonly property Process workspacePoll: Process {
        command: ["niri", "msg", "--json", "workspaces"]
        running: true

        stdout: StdioCollector {
            id: workspaceOutput

            onStreamFinished: root.acceptWorkspaces(workspaceOutput.text)
        }
    }

    readonly property Timer pollTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (!root.workspacePoll.running)
                root.workspacePoll.running = true;
        }
    }
}
