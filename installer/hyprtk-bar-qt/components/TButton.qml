// Themed push button (replaces the raw QtQuick Controls Basic look).
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

Button {
    id: root

    implicitHeight: 30
    implicitWidth: Math.max(64, contentItem.implicitWidth + 24)
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily

    contentItem: Text {
        text: root.text
        font: root.font
        color: root.enabled ? Theme.foreground : Theme.dim
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: !root.enabled ? Theme.alpha(Theme.dim, 0.08)
            : root.down ? Theme.alpha(Theme.accent, 0.40)
            : root.hovered ? Theme.alpha(Theme.accent2, 0.28)
            : Theme.alpha(Theme.accent2, 0.14)
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, root.enabled ? 0.35 : 0.15)
    }
}
