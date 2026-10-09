// Themed toggle rendered as a traditional radio button (ring + inner dot).
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

CheckBox {
    id: root

    spacing: 8
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    implicitHeight: 26

    contentItem: Text {
        text: root.text
        font: root.font
        color: root.enabled ? Theme.foreground : Theme.dim
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
    }

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: root.leftPadding
        y: parent.height / 2 - height / 2
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: root.checked ? Theme.accent : Theme.alpha(Theme.accent2, 0.5)

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.5)
            height: width
            radius: width / 2
            color: Theme.accent
            visible: root.checked
        }
    }
}
