// Themed tooltip (a single shared layer-shell popup).
//
// Declared once at a stable item (Bar.qml) and anchored to the currently
// hovered module via the Tooltips singleton. Quickshell popups fail to map when
// declared inside a Repeater delegate, hence the shared-instance design.
import QtQuick
import Quickshell
import "../theme"
import "../config"
import "../data"

PopupWindow {
    id: tip

    property var anchorWin: null

    visible: Tooltips.show && Tooltips.lines.length > 0 && Tooltips.target !== null
    color: "transparent"

    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: tip.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: tip.reveal = visible ? 1 : 0

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
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.panelOpacityStrong)
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, 0.3)
        opacity: tip.reveal
        transform: Translate { y: (1 - tip.reveal) * -8 }

        Text {
            id: label
            anchors.centerIn: parent
            text: Tooltips.text
            color: Theme.foreground
            font.pixelSize: 11
            horizontalAlignment: Tooltips.lines.length > 1 ? Text.AlignLeft : Text.AlignHCenter
            lineHeight: 1.15
        }
    }
}
