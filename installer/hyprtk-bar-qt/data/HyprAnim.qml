// Hyprland border-animation mirror for the bar border (backend reads the
// active animations-*.lua). `periodMs` = 0 means "unknown" (use the local
// fallback in Bar.qml).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/hypr_animations.py").toString().replace("file://", "")

    property int periodMs: 0

    function reload() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: ["python3", root.backend, "period"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const p = JSON.parse(line).period_ms;
                    root.periodMs = (p && p > 0) ? p : 0;
                } catch (e) {}
            }
        }
    }

    // Re-read when the Qt config (animations mode / border_animation) changes.
    Connections {
        target: BarConfig
        function onCfgChanged() { root.reload() }
    }
    Component.onCompleted: root.reload()
}
