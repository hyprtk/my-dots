// System tray (SNI host), via Quickshell's StatusNotifier + DBusMenu services.
//
// Left-click activates, middle-click secondary-activates, right-click opens the
// item's DBusMenu context menu through QsMenuAnchor (items with onlyMenu open
// the menu on left-click too).
//
// Each item is drawn as a Nerd Font glyph chosen from its SNI id/icon/title
// (e.g. nm-applet's wired vs wireless icon → ethernet vs Wi-Fi glyph), not the
// app-provided pixmap.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../data"

RowLayout {
    id: root
    spacing: 6
    visible: BarConfig.tray.enabled !== false

    readonly property int iconSize: BarConfig.tray.icon_size || 18

    // Lower-cased id + icon name + title, used to pick a glyph/colour.
    function _info(it) {
        return (String(it.id || "") + " " + String(it.icon || "") + " " + String(it.title || "")).toLowerCase();
    }
    function trayGlyph(it) {
        const s = root._info(it);
        if (s.indexOf("wireless") >= 0 || s.indexOf("wifi") >= 0 || s.indexOf("wi-fi") >= 0 || s.indexOf("wlan") >= 0)
            return "\uf1eb";   // fa-wifi
        if (s.indexOf("wired") >= 0 || s.indexOf("ethernet") >= 0 || s.indexOf("nm-device") >= 0
            || s.indexOf("network") >= 0 || s.indexOf("nm-applet") >= 0 || s.indexOf("nm_applet") >= 0)
            return "\uef44";   // fa-ethernet
        if (s.indexOf("bluetooth") >= 0 || s.indexOf("blueman") >= 0)
            return "\uf293";   // fa-bluetooth-b
        if (s.indexOf("volume") >= 0 || s.indexOf("audio") >= 0 || s.indexOf("sound") >= 0 || s.indexOf("pulse") >= 0)
            return "\uf028";   // fa-volume-up
        if (s.indexOf("battery") >= 0 || s.indexOf("power") >= 0)
            return "\uf240";   // fa-battery-full
        if (s.indexOf("printer") >= 0 || s.indexOf("cups") >= 0)
            return "\uf02f";   // fa-print
        if (s.indexOf("clipboard") >= 0 || s.indexOf("clipman") >= 0)
            return "\uf0ea";   // fa-clipboard
        if (s.indexOf("mail") >= 0 || s.indexOf("envelope") >= 0)
            return "\uf0e0";   // fa-envelope
        if (s.indexOf("music") >= 0 || s.indexOf("player") >= 0 || s.indexOf("spotify") >= 0)
            return "\uf001";   // fa-music
        if (s.indexOf("chat") >= 0 || s.indexOf("discord") >= 0 || s.indexOf("telegram") >= 0
            || s.indexOf("signal") >= 0 || s.indexOf("slack") >= 0)
            return "\uf075";   // fa-comment
        if (s.indexOf("keyboard") >= 0)
            return "\uf11c";   // fa-keyboard
        if (s.indexOf("screenshot") >= 0 || s.indexOf("flameshot") >= 0)
            return "\uf083";   // fa-camera
        return "\uf111";       // generic dot fallback
    }
    function trayColor(it) {
        const s = root._info(it);
        if (s.indexOf("disabled") >= 0 || s.indexOf("inactive") >= 0)
            return Theme.dim;
        return Theme.foreground;
    }

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: item
            required property var modelData

            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            // Window attached property is only valid on Item-derived types, so
            // resolve it here and hand it to the (QtObject) menu anchor.
            readonly property var barWindow: QsWindow.window

            HoverHandler {
                id: trayHover
                onHoveredChanged: (trayHover.hovered && item.modelData.title)
                    ? Tooltips.showTip(item, item.modelData.title)
                    : Tooltips.hideTip()
            }
            Text {
                anchors.centerIn: parent
                text: root.trayGlyph(item.modelData)
                color: root.trayColor(item.modelData)
                font.family: BarConfig.glyphFont
                font.pixelSize: Math.round(root.iconSize * 0.85)
            }

            QsMenuAnchor {
                id: menuAnchor
                menu: item.modelData.menu
                anchor.window: item.barWindow
                anchor.item: item
                anchor.rect: Qt.rect(0, item.height, item.width, 1)
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) {
                        item.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        if (item.modelData.hasMenu)
                            menuAnchor.open();
                    } else if (item.modelData.onlyMenu) {
                        if (item.modelData.hasMenu)
                            menuAnchor.open();
                        else
                            item.modelData.activate();
                    } else {
                        item.modelData.activate();
                    }
                }
            }
        }
    }
}
