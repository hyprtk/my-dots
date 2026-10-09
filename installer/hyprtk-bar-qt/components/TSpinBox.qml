// Themed spin box (numeric field with up/down steppers).
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

SpinBox {
    id: root

    implicitHeight: 30
    implicitWidth: 120
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily

    contentItem: TextInput {
        text: root.textFromValue(root.value, root.locale)
        font: root.font
        color: Theme.foreground
        selectionColor: Theme.accent
        selectedTextColor: "#000000"
        horizontalAlignment: Qt.AlignLeft
        verticalAlignment: Qt.AlignVCenter
        readOnly: !root.editable
        validator: root.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        leftPadding: 9
        rightPadding: 26
    }

    up.indicator: Rectangle {
        x: root.width - width
        y: 0
        width: 22
        height: root.height / 2
        color: root.up.pressed ? Theme.alpha(Theme.accent, 0.5)
            : root.up.hovered ? Theme.alpha(Theme.accent2, 0.28) : "transparent"
        Text { anchors.centerIn: parent; text: "\uf077"; color: Theme.dim; font.pixelSize: 9 }
    }

    down.indicator: Rectangle {
        x: root.width - width
        y: root.height / 2
        width: 22
        height: root.height / 2
        color: root.down.pressed ? Theme.alpha(Theme.accent, 0.5)
            : root.down.hovered ? Theme.alpha(Theme.accent2, 0.28) : "transparent"
        Text { anchors.centerIn: parent; text: "\uf078"; color: Theme.dim; font.pixelSize: 9 }
    }

    background: Rectangle {
        radius: 6
        color: Theme.alpha(Theme.background, 0.6)
        border.width: 1
        border.color: root.activeFocus ? Theme.accent : Theme.alpha(Theme.accent2, 0.30)
    }
}
