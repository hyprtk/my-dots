// Small labelled pill button used for panel clear/confirm and toast actions.
import QtQuick
import "../theme"
import "../data"

Rectangle {
    id: root

    property string label: ""
    property color baseColor: Theme.alpha(Theme.accent, 0.25)
    property color hoverColor: Theme.alpha(Theme.accent2, 0.30)
    property color textColor: Theme.foreground
    property int textPixelSize: BarConfig.scaled(11)
    signal tapped()

    implicitWidth: labelText.implicitWidth + 18
    implicitHeight: 24
    radius: 6
    color: pillHover.hovered ? root.hoverColor : root.baseColor

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.textColor
        font.pixelSize: root.textPixelSize
    }

    HoverHandler { id: pillHover }
    TapHandler { onTapped: root.tapped() }
}
