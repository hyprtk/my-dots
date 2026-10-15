// System tray (SNI host), via Quickshell's StatusNotifier + DBusMenu services.
//
// Left-click activates, middle-click secondary-activates, right-click opens the
// item's DBusMenu context menu (items with onlyMenu open the menu on left-click
// too), so the network indicator's NetworkManager menu (Wi-Fi/VPN toggles,
// Connection Information, Edit Connections…) is the app's own. The menu is
// rendered by TrayMenuPopup (a frosted, pywal-themed panel) rather than a
// native Qt menu, which could not match the bar theme.
//
// Hovering shows a rich tooltip: the network indicator reports the active
// connection, device, IPv4/gateway and up/down rates; blueman reports the
// adapter state and connected devices. Other items fall back to their title.
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

    // The tray item currently hovered, so live TrayInfo updates can refresh the
    // open tooltip (network rates change every couple of seconds).
    property var hoveredItem: null

    Connections {
        target: TrayInfo
        function onNetworkChanged() { root._refreshTip(); }
        function onBluetoothChanged() { root._refreshTip(); }
        function onReadyChanged() { root._refreshTip(); }
    }


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
    // nm-applet (the NetworkManager indicator): left-click opens the connection
    // editor, matching the GTK bar. Its own activate()/menu does nothing useful
    // in a Quickshell host.
    function isNmApplet(it) {
        const s = root._info(it);
        return s.indexOf("nm-applet") >= 0 || s.indexOf("nm_applet") >= 0;
    }

    // Which rich tooltip an item gets ("network" / "bluetooth"), or "" for a
    // plain title tooltip.
    function trayKind(it) {
        const s = root._info(it);
        if (s.indexOf("wireless") >= 0 || s.indexOf("wifi") >= 0 || s.indexOf("wi-fi") >= 0
            || s.indexOf("wlan") >= 0 || s.indexOf("wired") >= 0 || s.indexOf("ethernet") >= 0
            || s.indexOf("nm-device") >= 0 || s.indexOf("nm-applet") >= 0
            || s.indexOf("network") >= 0)
            return "network";
        if (s.indexOf("bluetooth") >= 0 || s.indexOf("blueman") >= 0)
            return "bluetooth";
        return "";
    }

    function _tipLines(it) {
        const kind = root.trayKind(it);
        if (kind === "network" && TrayInfo.ready)
            return TrayInfo.networkLines();
        if (kind === "bluetooth" && TrayInfo.ready)
            return TrayInfo.bluetoothLines();
        const title = it.title || it.tooltipTitle || "";
        return title ? [title] : [];
    }

    // `del` is the delegate Item (the tooltip anchor); its modelData is the SNI.
    function showItemTip(del) {
        root.hoveredItem = del;
        const lines = root._tipLines(del.modelData);
        if (lines.length)
            Tooltips.showLines(del, lines);
        else
            Tooltips.hideTip();
    }

    function _refreshTip() {
        if (root.hoveredItem)
            root.showItemTip(root.hoveredItem);
    }

    function clearTip(del) {
        if (root.hoveredItem !== del)
            return;
        root.hoveredItem = null;
        Tooltips.hideTip();
    }

    // Open the item's DBusMenu in the themed popup (`del` is the delegate Item,
    // used as the menu anchor; its modelData carries the menu handle).
    function _openMenu(del) {
        if (del.modelData.hasMenu && del.modelData.menu)
            TrayMenu.open(del, del.modelData.menu);
    }

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: item
            required property var modelData

            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            HoverHandler {
                id: trayHover
                onHoveredChanged: trayHover.hovered
                    ? root.showItemTip(item)
                    : root.clearTip(item)
            }
            Text {
                anchors.centerIn: parent
                text: root.trayGlyph(item.modelData)
                color: root.trayColor(item.modelData)
                font.family: BarConfig.glyphFont
                font.pixelSize: Math.round(root.iconSize * 0.85)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) {
                        item.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        root.clearTip(item);
                        root._openMenu(item);
                    } else if (root.isNmApplet(item.modelData)) {
                        Quickshell.execDetached(["nm-connection-editor"]);
                    } else if (item.modelData.onlyMenu) {
                        if (item.modelData.hasMenu)
                            root._openMenu(item);
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
