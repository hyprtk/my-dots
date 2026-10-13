// Desktop-widget move mode (cursor-polling drag).
//
// A Hyprland bind (Super+Shift+left) writes start/stop to a FIFO the
// widget_move.py streamer relays here; while moving we poll the cursor and
// offset the widget under it, persisting its free position on release.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string moveBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/widget_move.py").toString().replace("file://", "")
    readonly property string saveBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/widgets_layout.py").toString().replace("file://", "")

    property bool moving: false
    property string movingId: ""
    property bool selecting: false
    property real startX: 0
    property real startY: 0
    property int baseX: 0
    property int baseY: 0
    property real curX: 0
    property real curY: 0
    property string status: ""

    // id -> {x, y, w, h} registered by each widget frame.
    property var rects: ({})

    // Boundary: no widget may pass outside the area inset from every screen
    // edge by the bar height + 3px (matches WidgetFrame / WidgetLayout).
    readonly property int boundary: Math.max(0, BarConfig.barHeight + 3)

    // Clamp a widget rect (x, y, w, h) inside the boundary.
    function _clamp(x, y, w, h) {
        const s = Screens.focused();
        const sw = s ? s.width : 0;
        const sh = s ? s.height : 0;
        const b = root.boundary;
        const maxX = Math.max(b, sw - b - w);
        const maxY = Math.max(b, sh - b - h);
        return {
            x: Math.round(Math.min(Math.max(x, b), maxX)),
            y: Math.round(Math.min(Math.max(y, b), maxY))
        };
    }

    // id -> {x, y}: a just-dropped position held until the config reload
    // confirms it. Without this the widget reverts to its old margin for a
    // frame (the async save has not landed yet) — a "boomerang".
    property var committed: ({})

    function setGeometry(id, x, y, w, h) {
        if (!id)
            return;
        const prev = root.rects[id];
        if (prev && prev.x === x && prev.y === y && prev.w === w && prev.h === h)
            return;
        const r = Object.assign({}, root.rects);
        r[id] = { x: x, y: y, w: w, h: h };
        root.rects = r;
    }

    function overFor(id) {
        // NOTE: must not read root.rects here — this is evaluated in the
        // WidgetFrame `moveOver` binding, and rects is written by setGeometry
        // (triggered by effMarginX), which would loop. Clamping happens in
        // _cursor/_beginAt/stop instead.
        if (root.moving && root.movingId === id)
            return {
                x: Math.round(root.baseX + (root.curX - root.startX)),
                y: Math.round(root.baseY + (root.curY - root.startY)),
                w: -1, h: -1
            };
        const c = root.committed[id];
        if (c)
            return { x: c.x, y: c.y, w: -1, h: -1 };
        return null;
    }

    function hitTest(cx, cy) {
        for (const id in root.rects) {
            const r = root.rects[id];
            if (cx >= r.x && cx <= r.x + r.w && cy >= r.y && cy <= r.y + r.h)
                return id;
        }
        return "";
    }

    function start() {
        if (root.moving)
            return;
        root.selecting = true;
        cursorProc.running = true;
    }
    function _beginAt(cx, cy) {
        const id = root.hitTest(cx, cy);
        root.selecting = false;
        if (!id) {
            root.status = "No widget under cursor";
            return;
        }
        root.movingId = id;
        const r = root.rects[id];
        root.baseX = r.x;
        root.baseY = r.y;
        root.startX = cx;
        root.startY = cy;
        root.curX = cx;
        root.curY = cy;
        root.moving = true;
        root.status = "Moving " + id;
    }
    function stop() {
        if (!root.moving) {
            root.selecting = false;
            return;
        }
        const id = root.movingId;
        const r = root.rects[id];
        const cl = root._clamp(root.baseX + (root.curX - root.startX),
                               root.baseY + (root.curY - root.startY),
                               r ? r.w : 0, r ? r.h : 0);
        const x = cl.x;
        const y = cl.y;
        // Hold the dropped position until the config reload reflects it.
        const c = Object.assign({}, root.committed);
        c[id] = { x: x, y: y };
        root.committed = c;
        // Persist + snap to the nearest adjacent widget (if any).
        saveProc.command = ["python3", root.saveBackend, "snap",
            "--id", id, "--x", String(x), "--y", String(y),
            "--rects", JSON.stringify(root.rects)];
        saveProc.running = true;
        settleTimer.interval = 1500;
        settleTimer.restart();
        root.moving = false;
        root.movingId = "";
        root.status = "";
    }

    Timer { id: settleTimer; interval: 500; onTriggered: root.committed = ({}) }

    Process {
        id: fifoProc
        running: true
        command: ["python3", "-u", root.moveBackend]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const c = JSON.parse(line).cmd;
                    if (c === "start")
                        root.start();
                    else if (c === "stop")
                        root.stop();
                    else if (c === "toggle")
                        root.moving ? root.stop() : root.start();
                } catch (e) {}
            }
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: SplitParser { onRead: line => root._cursor(line) }
    }
    Process {
        id: saveProc
        onExited: (code, status) => {
            root.status = code === 0 ? "Saved" : "Save failed";
            if (code === 0) {
                settleTimer.interval = 500;
                settleTimer.restart();
            } else {
                root.committed = ({});
            }
        }
    }
    Timer {
        running: root.moving
        interval: 70
        repeat: true
        onTriggered: cursorProc.running = true
    }
    function _cursor(line) {
        const m = String(line).match(/(-?\d+)\s*,\s*(-?\d+)/);
        if (!m)
            return;
        const cx = parseInt(m[1]);
        const cy = parseInt(m[2]);
        if (root.selecting) {
            root._beginAt(cx, cy);
        } else if (root.moving) {
            // Clamp the target (base + cursor delta) inside the boundary, then
            // store it back as a cursor offset so overFor (a binding) stays free
            // of the rect read that would otherwise loop via setGeometry.
            const r = root.rects[root.movingId];
            const cl = root._clamp(root.baseX + (cx - root.startX),
                                   root.baseY + (cy - root.startY),
                                   r ? r.w : 0, r ? r.h : 0);
            root.curX = root.startX + (cl.x - root.baseX);
            root.curY = root.startY + (cl.y - root.baseY);
        }
    }
}
