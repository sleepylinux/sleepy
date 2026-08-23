import QtQuick

Item {
    id: root

    required property url source

    implicitWidth: 36
    implicitHeight: 36

    Image {
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
