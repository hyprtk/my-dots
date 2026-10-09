// Window list (tasklist): one button per app, grouped by appId, with optional
// pinned apps from the `center.pinned` config.
//
// Left-click activates the app's most-recent window, or minimises it when it is
// already focused; middle-click closes it; a pinned app with no window launches
// its command. Backed by the Quickshell Hyprland service (HyprlandToplevel:
// title / activated / address / workspace), with actions dispatched by address.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../theme"
import "../../data"

RowLayout {
    id: root
    spacing: 4
    readonly property int fs: BarConfig.fontSize(11)
    readonly property var pinned: (BarConfig.center.pinned || [])

    function _appId(t) {
        return (t.wayland && t.wayland.appId) ? t.wayland.appId : (t.title || "app");
    }
    // Resolve an appId to a theme icon (desktop entry, symbolic preferred).
    function iconFor(appId) {
        let e = null;
        try {
            e = DesktopEntries.byId(appId)
                || DesktopEntries.byId(appId + ".desktop")
                || DesktopEntries.heuristicLookup(appId);
        } catch (err) {}
        let name = (e && e.icon) ? e.icon : appId;
        if (name && Quickshell.hasThemeIcon(name + "-symbolic"))
            name = name + "-symbolic";
        return Quickshell.iconPath(name, "application-x-executable");
    }
    function _match(a, b) {
        a = String(a || "").toLowerCase().replace(/\.desktop$/, "");
        b = String(b || "").toLowerCase().replace(/\.desktop$/, "");
        return a.length > 0 && b.length > 0 && (a === b || a.includes(b) || b.includes(a));
    }
    function groups() {
        const map = {};
        for (const t of (Hyprland.toplevels.values || [])) {
            const k = root._appId(t);
            (map[k] = map[k] || []).push(t);
        }
        const out = [];
        const seen = {};
        for (const p of root.pinned) {
            let key = null;
            for (const k in map)
                if (root._match(p.class, k)) { key = k; break; }
            out.push({ pinned: p, appId: p.class || "", wins: key ? map[key] : [] });
            if (key)
                seen[key] = true;
        }
        for (const k in map)
            if (!seen[k])
                out.push({ pinned: null, appId: k, wins: map[k] });
        return out;
    }
    function _recent(wins) {
        return wins.find(w => w.activated) || wins[0];
    }
    // Focus a window, restoring it first if it is parked on a special
    // (negative-id) workspace such as special:minimized — matches the GTK bar.
    function _focusWindow(w) {
        if (!w || !w.address)
            return;
        if (w.workspace && w.workspace.id < 0) {
            const aw = Hyprland.focusedWorkspace;
            if (aw)
                Hyprland.dispatch(Hypr.moveWindowTo(aw.name || String(aw.id), w.address));
        }
        Hyprland.dispatch(Hypr.focusWindow(w.address));
    }
    function _menu(grp) {
        const w = root._recent(grp.wins);
        const items = [];
        if (w) {
            items.push({ label: "Minimise", action: () => {
                if (w.address) Hyprland.dispatch(Hypr.moveWindowTo("special:minimized", w.address));
            } });
            items.push({ label: "Close window", action: () => {
                if (w.address) Hyprland.dispatch(Hypr.closeWindow(w.address));
            } });
        } else if (grp.modelData.pinned && grp.modelData.pinned.command) {
            items.push({ label: "Launch", action: () => Quickshell.execDetached(["sh", "-c", grp.modelData.pinned.command]) });
        }
        PopupMenu.open(grp, items);
    }

    Repeater {
        model: root.groups()

        delegate: Rectangle {
            id: grp
            required property var modelData

            readonly property var wins: grp.modelData.wins
            readonly property var pin: grp.modelData.pinned
            readonly property string appId: grp.modelData.appId
            readonly property bool act: grp.wins.some(w => w.activated)
            readonly property bool running: grp.wins.length > 0
            readonly property var recent: root._recent(grp.wins)
            readonly property string title: grp.running
                ? (grp.recent.title || grp.appId)
                : (grp.pin && grp.pin.class ? grp.pin.class : "?")

            implicitWidth: 26
            implicitHeight: 22
            radius: 6
            color: grp.act
                ? Theme.alpha(Theme.accent, 0.85)
                : (grp.running ? Theme.alpha(Theme.accent2, 0.12) : Theme.alpha(Theme.dim, 0.18))

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: root.iconFor(grp.appId)
                opacity: grp.running ? 1.0 : 0.6
            }

            // running indicator (bottom-right)
            Rectangle {
                visible: grp.running
                width: 4
                height: 4
                radius: 2
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                color: grp.act ? "#000000" : Theme.accent2
            }

            HoverHandler {
                id: grpHover
                onHoveredChanged: grpHover.hovered
                    ? Tooltips.showTip(grp, grp.title)
                    : Tooltips.hideTip()
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root._menu(grp);
                        return;
                    }
                    const wins = grp.wins;
                    if (!wins.length) {
                        if (mouse.button === Qt.LeftButton && grp.pin && grp.pin.command)
                            Quickshell.execDetached(["sh", "-c", grp.pin.command]);
                        return;
                    }
                    const focused = wins.find(w => w.activated);
                    if (mouse.button === Qt.MiddleButton) {
                        const w = focused || root._recent(wins);
                        if (w.address)
                            Hyprland.dispatch(Hypr.closeWindow(w.address));
                        return;
                    }
                    if (focused) {
                        if (focused.address)
                            Hyprland.dispatch(Hypr.moveWindowTo("special:minimized", focused.address));
                        return;
                    }
                    root._focusWindow(root._recent(wins));
                }
            }
        }
    }
}
