// Themed slider.
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

Slider {
    id: root

    implicitHeight: 24

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 4
        radius: 2
        color: Theme.alpha(Theme.dim, 0.30)

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.accent
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 16
        height: 16
        radius: 8
        color: root.pressed ? Theme.accent2 : Theme.accent
        border.width: 2
        border.color: Theme.alpha(Theme.background, 0.9)
    }
}
