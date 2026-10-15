// Themed tray context menu (a single shared layer-shell popup).
//
// A native Qt platform menu (QsMenuAnchor) can't wear the bar's pywal theme
// without global qt6ct styling, so the SNI item's DBusMenu is rendered here
// instead: a frosted panel matching the bar, driven by QsMenuOpener. Submenus
// (e.g. nm-applet's "VPN Connections") drill down in place with a Back row —
// Quickshell popups don't map inside a Repeater, so one popup hosts every level.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../config"
import "../data"

PopupWindow {
    id: menu

    property var anchorWin: null
    // Drill-down trail: [{label, handle}]; the last entry is the visible level.
    property var trail: []
    readonly property var current: menu.trail.length ? menu.trail[menu.trail.length - 1] : null

    visible: TrayMenu.show && TrayMenu.handle !== null && TrayMenu.target !== null
    color: "transparent"
    grabFocus: true
    onClosed: TrayMenu.close()

    // Sit clear of the whole bar, not on top of it: the icon is centred in the
    // bar, so offset the anchor from the icon to the bar's outer edge (+ gap).
    readonly property bool barAtTop: BarConfig.barPosition === "top"
    readonly property int iconH: TrayMenu.target ? TrayMenu.target.height : 0
    readonly property int iconW: TrayMenu.target ? TrayMenu.target.width : 0
    readonly property int edgeGap: Math.round((BarConfig.barHeight - menu.iconH) / 2) + 6

    // Start a fresh trail whenever the menu is (re)opened.
    Connections {
        target: TrayMenu
        function onShowChanged() {
            if (TrayMenu.show)
                menu.trail = [{ label: "", handle: TrayMenu.handle }];
        }
    }

    QsMenuOpener {
        id: opener
        menu: menu.current ? menu.current.handle : null
    }

    implicitWidth: panel.implicitWidth + 8
    implicitHeight: panel.implicitHeight + 8

    Shortcut {
        sequence: "Escape"
        onActivated: menu.back()
    }

    anchor.window: menu.anchorWin
    anchor.item: TrayMenu.target
    // Anchor at the bar's outer edge, clear of it, and grow inwards from the
    // icon (the tray sits in the bar's right section, so the menu opens left).
    anchor.rect: Qt.rect(0, menu.barAtTop ? menu.iconH + menu.edgeGap : -menu.edgeGap,
                         menu.iconW, 1)
    anchor.edges: menu.barAtTop ? (Edges.Bottom | Edges.Right) : (Edges.Top | Edges.Right)
    anchor.gravity: menu.barAtTop ? (Edges.Bottom | Edges.Left) : (Edges.Top | Edges.Left)
    anchor.adjustment: PopupAdjustment.SlideX

    function activate(entry) {
        if (!entry || entry.isSeparator || entry.enabled === false)
            return;
        if (entry.hasChildren) {
            menu.trail = menu.trail.concat([{ label: entry.text, handle: entry }]);
            return;
        }
        entry.triggered();
        TrayMenu.close();
    }

    function back() {
        if (menu.trail.length > 1)
            menu.trail = menu.trail.slice(0, -1);
        else
            TrayMenu.close();
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPopup
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.panelOpacityStrong)
        border.width: BarConfig.borderWidth
        border.color: Theme.alpha(Theme.accent2, 0.25)

        ColumnLayout {
            id: panel
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Rectangle {
                visible: menu.trail.length > 1
                Layout.fillWidth: true
                implicitHeight: 26
                implicitWidth: backText.implicitWidth + 24
                radius: 6
                color: backHover.hovered ? Theme.alpha(Theme.accent2, 0.18) : "transparent"

                Text {
                    id: backText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "\u2039  " + (menu.current ? menu.current.label : "Back")
                    color: Theme.accent2
                    font.pixelSize: BarConfig.scaled(12)
                }
                HoverHandler { id: backHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.back()
                }
            }

            Repeater {
                model: opener.children

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool isSep: row.modelData.isSeparator
                    readonly property bool active: !row.isSep && row.modelData.enabled !== false
                    readonly property bool kids: row.modelData.hasChildren
                    readonly property bool checkable: !row.isSep && row.modelData.buttonType !== 0

                    Layout.fillWidth: true
                    implicitHeight: row.isSep ? 9 : 28
                    implicitWidth: row.isSep ? 0
                        : rowText.implicitWidth + 24 + (row.checkable ? 18 : 0) + (row.kids ? 16 : 0)
                    radius: 6
                    color: (row.active && rowHover.hovered) ? Theme.alpha(Theme.accent2, 0.18) : "transparent"
                    opacity: (row.isSep || row.active) ? 1 : 0.5

                    HoverHandler { id: rowHover; enabled: row.active }

                    Rectangle {
                        visible: row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        height: 1
                        color: Theme.alpha(Theme.foreground, 0.14)
                    }

                    Text {
                        id: checkGlyph
                        visible: row.checkable
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        width: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.checkState === 2 ? "\u2713"
                            : (row.modelData.checkState === 1 ? "\u2022" : "")
                        color: Theme.accent
                        font.pixelSize: BarConfig.scaled(11)
                    }

                    Text {
                        id: rowText
                        visible: !row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: row.checkable ? checkGlyph.right : parent.left
                        anchors.leftMargin: row.checkable ? 2 : 12
                        anchors.right: row.kids ? chevron.left : parent.right
                        anchors.rightMargin: row.kids ? 4 : 12
                        text: row.modelData.text || ""
                        color: Theme.foreground
                        font.pixelSize: BarConfig.scaled(12)
                        elide: Text.ElideRight
                    }

                    Text {
                        id: chevron
                        visible: row.kids
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: "\u203a"
                        color: Theme.dim
                        font.pixelSize: BarConfig.scaled(13)
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: row.active
                        cursorShape: row.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: menu.activate(row.modelData)
                    }
                }
            }
        }
    }
}
