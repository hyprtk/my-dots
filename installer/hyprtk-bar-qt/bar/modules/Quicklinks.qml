// Quick links: a configurable row of launcher glyphs (the Qt `quicklinks.links`
// block). Left-click runs `command`; right/middle-click runs
// `command_right` / `command_middle` when set; a few ids open a Qt surface.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../config"
import "../../state"
import "../../data"

RowLayout {
    id: root
    spacing: 4
    visible: BarConfig.quicklinks.enabled !== false
    readonly property int fs: BarConfig.fontSize(13)
    readonly property int iconSize: BarConfig.quicklinks.icon_size || 22
    readonly property var links: {
        const l = BarConfig.quicklinks.links;
        return (l && l.length) ? l : Config.quicklinksLinks;
    }

    // Empty terminal/files/web commands resolve to the session default.
    function defaultCommand(id) {
        if (id === "terminal")
            return Quickshell.env("TERMINAL") || "alacritty";
        if (id === "files")
            return Quickshell.env("FILEMANAGER") || "thunar";
        if (id === "web")
            return Quickshell.env("BROWSER") || "brave";
        return "";
    }

    Repeater {
        model: root.links

        delegate: Rectangle {
            id: link
            required property var modelData

            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
            radius: 6
            color: hover.hovered ? Theme.alpha(Theme.accent2, 0.22) : "transparent"

            Text {
                anchors.centerIn: parent
                text: link.modelData.icon || link.modelData.glyph || "\u2022"
                color: Theme.accent
                font.pixelSize: root.fs
                font.family: BarConfig.quicklinks.glyph_font || BarConfig.glyphFont
            }

            HoverHandler {
                id: hover
                onHoveredChanged: (hover.hovered && (link.modelData.label || link.modelData.id))
                    ? Tooltips.showTip(link, link.modelData.label || link.modelData.id)
                    : Tooltips.hideTip()
            }

            // Register our window-relative position so the clipboard/themer
            // panels line up under the glyph that opens them.
            readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""
            function _registerAnchor() {
                const id = link.modelData.id || "";
                const action = link.modelData.action || "";
                const x = link.mapToItem(null, 0, 0).x;
                if (id === "cliphist" || action === "clipboard")
                    BarAnchors.setClip(x, link.width, link.screenName);
                if (id === "wallpaper" || action === "themer")
                    BarAnchors.setThemer(x, link.width, link.screenName);
            }
            Component.onCompleted: _registerAnchor()
            onXChanged: _registerAnchor()
            onWidthChanged: _registerAnchor()
            onScreenNameChanged: _registerAnchor()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    const d = link.modelData;
                    const id = d.id || "";
                    const right = d.command_right || d.alt || "";
                    const middle = d.command_middle || "";
                    if (mouse.button === Qt.LeftButton) {
                        if (id === "cliphist") { UiState.clipboardOpen = !UiState.clipboardOpen; return; }
                        if (id === "wallpaper") { UiState.themerOpen = !UiState.themerOpen; return; }
                        if (d.action === "clipboard") { UiState.clipboardOpen = !UiState.clipboardOpen; return; }
                        if (d.action === "themer") { UiState.themerOpen = !UiState.themerOpen; return; }
                        const cmd = d.command || root.defaultCommand(id);
                        if (cmd) Quickshell.execDetached(["sh", "-c", cmd]);
                    } else if (mouse.button === Qt.RightButton) {
                        if (right) Quickshell.execDetached(["sh", "-c", right]);
                    } else if (mouse.button === Qt.MiddleButton) {
                        if (middle) Quickshell.execDetached(["sh", "-c", middle]);
                    }
                }
            }
        }
    }
}
