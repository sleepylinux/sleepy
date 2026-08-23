import QtQuick

QtObject {
    id: root

    property date currentTime: new Date()
    readonly property string time: Qt.formatTime(root.currentTime, "HH:mm")

    readonly property Timer updateTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.currentTime = new Date()
    }
}
