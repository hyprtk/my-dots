// Shared progress/meter bar: a rounded track with a fraction-filled inner bar.
import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: root

    property real fraction: 0
    property color trackColor: Theme.alpha(Theme.dim, 0.25)
    property color fillColor: Theme.accent

    Layout.fillWidth: true
    radius: height / 2
    color: root.trackColor

    Rectangle {
        width: parent.width * Math.min(Math.max(root.fraction, 0), 1)
        height: parent.height
        radius: parent.radius
        color: root.fillColor
    }
}
