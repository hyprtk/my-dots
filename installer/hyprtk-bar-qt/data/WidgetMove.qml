// Desktop-widget move mode (cursor-polling drag).
//
// A Hyprland bind (Super+Shift+left) writes start/stop to a FIFO the
// widget_move.py streamer relays here; while moving we poll the cursor and
// offset the widget under it, persisting its free position on release.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
        const x = Math.round(root.baseX + (root.curX - root.startX));
        const y = Math.round(root.baseY + (root.curY - root.startY));
        // Hold the dropped position until the config reload reflects it.
        const c = Object.assign({}, root.committed);
        c[id] = { x: x, y: y };
        root.committed = c;
        // Persist + snap to the nearest adjacent widget (if any).
        saveProc.command = ["python3", root.saveBackend, "snap",
            "--id", id, "--x", String(x), "--y", String(y),
            "--rects", JSON.stringify(root.rects)];
        saveProc.running = true;
        // Hold the dropped position until the async layout has caught up (else
        // the widget flashes to its stale layout slot for a frame).
        settleTimer.restart();
        root.moving = false;
        root.movingId = "";
        root.status = "";
    }

    // Clears the drop override once the config reload (debounce 120ms) and the
    // layout process have both had time to run.
    Timer { id: settleTimer; interval: 350; onTriggered: root.committed = ({}) }

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
        onExited: (code, status) => { root.status = code === 0 ? "Saved" : "Save failed"; }
    }
    Timer {
        running: root.moving
        interval: 30
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
            root.curX = cx;
            root.curY = cy;
        }
    }
}
