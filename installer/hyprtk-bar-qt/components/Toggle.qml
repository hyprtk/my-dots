// A small pill toggle matching the hyprtk look (no QtQuick.Controls styling).
import QtQuick
import "../theme"
import "../config"

Item {
    id: root

    property bool checked: false
    property color onColor: Theme.accent
    property color offColor: Theme.accent2

    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 24

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked
            ? root.onColor
            : Qt.rgba(root.offColor.r, root.offColor.g, root.offColor.b, 0.35)
        Behavior on color { ColorAnimation { duration: Config.animationDuration } }

        Rectangle {
            id: knob
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: Theme.foreground
            Behavior on x { NumberAnimation { duration: Config.animationDuration } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
}
