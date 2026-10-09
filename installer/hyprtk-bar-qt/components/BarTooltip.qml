// Themed tooltip (a single shared layer-shell popup).
//
// Declared once at a stable item (Bar.qml) and anchored to the currently
// hovered module via the Tooltips singleton. Quickshell popups fail to map when
// declared inside a Repeater delegate, hence the shared-instance design.
import QtQuick
import Quickshell
import "../theme"
import "../data"

PopupWindow {
    id: tip

    property var anchorWin: null

    visible: Tooltips.show && Tooltips.text.length > 0 && Tooltips.target !== null
    color: "transparent"
    implicitWidth: label.implicitWidth + 18
    implicitHeight: label.implicitHeight + 8

    anchor.window: tip.anchorWin
    anchor.item: Tooltips.target
    anchor.rect: Qt.rect(0, Tooltips.target ? Tooltips.target.height : 0, Tooltips.target ? Tooltips.target.width : 0, 1)
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.95, Theme.opacity))
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, 0.3)

        Text {
            id: label
            anchors.centerIn: parent
            text: Tooltips.text
            color: Theme.foreground
            font.pixelSize: 11
        }
    }
}
