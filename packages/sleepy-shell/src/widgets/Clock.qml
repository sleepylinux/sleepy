import QtQuick

Item {
    id: root

    required property string time
    required property color textColor

    implicitWidth: 28
    implicitHeight: clockText.implicitHeight

    Text {
        id: clockText

        anchors.centerIn: parent
        text: root.time.replace(":", "\n")
        color: root.textColor
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 12
        font.weight: Font.Medium
        lineHeight: 0.9
    }
}
