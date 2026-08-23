pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../.." as Shell
import "../../services" as Services
import "../../widgets" as Widgets

Scope {
    id: root

    required property Shell.Theme theme
    required property Services.ClockService clockService
    required property Services.NiriService niriService
    required property url brandingSource

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panelWindow

            required property var modelData

            screen: modelData
            implicitWidth: root.theme.panelWidth
            color: root.theme.background

            anchors {
                top: true
                bottom: true
                left: true
            }

            Column {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: root.theme.spacing
                }
                spacing: root.theme.spacing

                Widgets.BrandMark {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: root.brandingSource
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.theme.spacing

                    Repeater {
                        model: root.niriService.workspaces

                        delegate: Widgets.WorkspaceButton {
                            required property var modelData

                            index: Number(modelData.idx)
                            active: Boolean(modelData.is_active)
                            activate: workspaceIndex => root.niriService.focusWorkspace(workspaceIndex)
                            theme: root.theme
                        }
                    }
                }
            }

            Widgets.Tray {
                anchors.centerIn: parent
                muted: root.theme.muted
            }

            Column {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: root.theme.spacing
                }
                spacing: root.theme.spacing

                Widgets.Clock {
                    anchors.horizontalCenter: parent.horizontalCenter
                    time: root.clockService.time
                    textColor: root.theme.text
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: root.theme.radius
                    color: root.theme.surface

                    Text {
                        anchors.centerIn: parent
                        text: "●"
                        color: root.theme.muted
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
