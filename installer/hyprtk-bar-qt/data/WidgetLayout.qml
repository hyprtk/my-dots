// Snap-group layout for the desktop widgets (layout comes from the backend).
//
// Widgets sharing a snap_group are laid out together; WidgetFrame reads the
// override for its id. Empty unless at least one widget has a snap_group.
//
// The backend needs each widget's *measured* size (auto-height widgets store
// height 0 in the config) and the usable area, so the process is re-run when
// the config or the measured sizes change.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/widgets_layout.py").toString().replace("file://", "")

    // Measured sizes (id -> {w, h}) registered by WidgetFrame.
    property var sizes: ({})
    property var layout: ({})
    property bool pending: false

    readonly property bool hasGroups: {
        const cfg = Widgets.cfg || ({});
        for (const k in cfg) {
            const b = cfg[k];
            if (b && typeof b === "object" && String(b.snap_group || "").length > 0)
                return true;
        }
        return false;
    }

    function setSize(id, w, h) {
        if (!id)
            return;
        const prev = root.sizes[id];
        if (prev && prev.w === w && prev.h === h)
            return;
        const s = Object.assign({}, root.sizes);
        s[id] = { w: w, h: h };
        root.sizes = s;
        root.schedule();
    }

    function schedule() {
        if (!root.hasGroups) {
            root.layout = ({});
            return;
        }
        reloadTimer.restart();
    }

    Timer { id: reloadTimer; interval: 120; onTriggered: root.reload() }

    function bounds() {
        const s = Screens.focused();
        if (!s)
            return { x0: 0, y0: 0, w: 0, h: 0 };
        // Usable area: the monitor minus the bar's reserved edge, as an origin
        // (x0/y0) plus size. The layout clamps the whole group into this, so its
        // top member is not shifted alone by the widget frame.
        const inset = BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn;
        const top = BarConfig.barPosition === "top" ? inset : 0;
        const bottom = BarConfig.barPosition === "bottom" ? inset : 0;
        return { x0: 0, y0: top, w: s.width, h: s.height - top - bottom };
    }

    function reload() {
        if (!root.hasGroups) {
            root.layout = ({});
            return;
        }
        if (proc.running) {
            root.pending = true;
            return;
        }
        proc.command = ["python3", root.backend, "layout",
            "--json", JSON.stringify(Widgets.cfg || ({})),
            "--heights", JSON.stringify(root.sizes),
            "--bounds", JSON.stringify(root.bounds())];
        proc.running = true;
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                try { root.layout = JSON.parse(line).layout || ({}); } catch (e) {}
            }
        }
        onExited: (code, status) => {
            if (root.pending) {
                root.pending = false;
                root.reload();
            }
        }
    }

    Connections {
        target: Widgets
        function onCfgChanged() { root.schedule(); }
    }
    Component.onCompleted: root.schedule()

    function forId(id) {
        return root.hasGroups ? (root.layout[id] || null) : null;
    }
}
