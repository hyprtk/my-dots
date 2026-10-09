// Workspace pills from the Quickshell Hyprland service. Click to switch.
// Honours the `workspaces` block (show_empty, max) and `font` size.
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"
import "../../data"

RowLayout {
    id: root
    spacing: 5
    visible: BarConfig.workspaces.enabled !== false

    readonly property bool showEmpty: BarConfig.workspaces.show_empty !== false
    readonly property int maxWs: BarConfig.workspaces.max || 6

    function _ws(id) {
        const list = Hyprland.workspaces.values || [];
        return list.find(w => w.id === id) || null;
    }
    function visibleIds() {
        const ids = new Set();
        let active = 0;
        for (const w of (Hyprland.workspaces.values || [])) {
            if (typeof w.id === "number" && w.id > 0)
                ids.add(w.id);
            if (w.active)
                active = w.id;
        }
        ids.add(active > 0 ? active : 1);
        if (root.showEmpty)
            for (let i = 1; i <= root.maxWs; i++)
                ids.add(i);
        return Array.from(ids).sort((a, b) => a - b);
    }
    function occupied(id) {
        const w = root._ws(id);
        return !!(w && w.toplevels && w.toplevels.values.length > 0);
    }
    function isActive(id) {
        const w = root._ws(id);
        return !!(w && w.active);
    }

    Repeater {
        model: root.visibleIds()

        delegate: Rectangle {
            id: pill
            required property var modelData

            readonly property bool act: root.isActive(pill.modelData)
            readonly property bool occ: root.occupied(pill.modelData)

            implicitWidth: 22
            implicitHeight: 22
            radius: 6
            color: pill.act ? Theme.accent
                : (pill.occ ? Theme.alpha(Theme.accent2, 0.32) : Theme.alpha(Theme.accent2, 0.15))

            Text {
                anchors.centerIn: parent
                text: pill.modelData
                color: pill.act ? "#000000" : Theme.foreground
                font.pixelSize: Math.max(9, BarConfig.fontSize(Theme.fontSize) - 1)
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch(Hypr.workspace(pill.modelData))
            }
            HoverHandler {
                id: pillHover
                onHoveredChanged: pillHover.hovered
                    ? Tooltips.showTip(pill, "Workspace " + pill.modelData)
                    : Tooltips.hideTip()
            }
        }
    }
}
