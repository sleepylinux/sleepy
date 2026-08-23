pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: root

    required property color muted

    implicitWidth: 28
    implicitHeight: trayColumn.implicitHeight

    Column {
        id: trayColumn

        width: parent.width
        spacing: 6

        Repeater {
            model: SystemTray.items

            delegate: Item {
                required property var modelData

                implicitWidth: root.implicitWidth
                implicitHeight: 24

                IconImage {
                    id: trayIcon

                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: parent.modelData.icon
                    visible: source.toString().length > 0
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: root.muted
                    visible: !trayIcon.visible
                }
            }
        }
    }
}
