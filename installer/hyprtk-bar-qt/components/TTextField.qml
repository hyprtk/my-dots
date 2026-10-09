// Themed text field.
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

TextField {
    id: root

    implicitHeight: 30
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    color: Theme.foreground
    placeholderTextColor: Theme.dim
    selectionColor: Theme.accent
    selectedTextColor: "#000000"
    leftPadding: 9
    rightPadding: 9

    background: Rectangle {
        radius: 6
        color: Theme.alpha(Theme.background, 0.6)
        border.width: 1
        border.color: root.activeFocus ? Theme.accent : Theme.alpha(Theme.accent2, 0.30)
    }
}
