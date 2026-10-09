// Themed context menu (a single shared layer-shell popup).
//
// Declared once at a stable item (Bar.qml) and anchored to the clicked module
// via the PopupMenu singleton (Quickshell popups fail to map inside a Repeater
// delegate, hence the shared-instance design).
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../data"

PopupWindow {
    id: menu

    property var anchorWin: null

    visible: PopupMenu.show && PopupMenu.items.length > 0 && PopupMenu.target !== null
    color: "transparent"
    implicitWidth: col.implicitWidth + 8
    implicitHeight: col.implicitHeight + 8
    grabFocus: true
    onClosed: PopupMenu.close()

    Shortcut {
        sequence: "Escape"
        onActivated: PopupMenu.close()
    }

    anchor.window: menu.anchorWin
    anchor.item: PopupMenu.target
    anchor.rect: Qt.rect(0, PopupMenu.target ? PopupMenu.target.height : 0, PopupMenu.target ? PopupMenu.target.width : 0, 1)
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.96, Theme.opacity))
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, 0.25)

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Repeater {
                model: PopupMenu.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitWidth: rowText.implicitWidth + 20
                    implicitHeight: 28
                    radius: 6
                    color: rowHover.hovered ? Theme.alpha(Theme.accent2, 0.18) : "transparent"

                    Text {
                        id: rowText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: row.modelData.label
                        color: Theme.foreground
                        font.pixelSize: 12
                    }

                    HoverHandler { id: rowHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const act = row.modelData.action;
                            PopupMenu.close();
                            if (act)
                                act();
                        }
                    }
                }
            }
        }
    }
}
