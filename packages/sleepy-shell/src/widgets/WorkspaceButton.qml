import QtQuick
import ".." as Shell

Rectangle {
    id: root

    required property int index
    required property bool active
    required property var activate
    required property Shell.Theme theme

    implicitWidth: 32
    implicitHeight: 32
    radius: root.theme.radius
    color: root.active ? root.theme.accent : "transparent"

    Text {
        anchors.centerIn: parent
        text: root.index
        color: root.active ? root.theme.background : root.theme.muted
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate(root.index)
    }
}
