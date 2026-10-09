// Keep the lock-screen config in step with the live pywal palette.
//
// Watches ~/.cache/wal/colors.json (rewritten by every `wal` run — wallpaper
// change, Theme Manager shuffle, "Re-apply Pywal Theme") and re-tints the
// active lock config via backend lock.py sync-pywal. Toolkit-free backend does
// the write; this only schedules it.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/lock.py").toString().replace("file://", "")

    FileView {
        id: walFile
        path: root.home + "/.cache/wal/colors.json"
        watchChanges: true
        printErrors: false
        onLoaded: debounce.restart()
        onTextChanged: debounce.restart()
        onFileChanged: reload()
    }
    // Collapse the burst of events a single `wal` run emits.
    Timer { id: debounce; interval: 500; onTriggered: root.sync() }
    Process { id: proc; command: ["python3", root.backend, "sync-pywal"] }

    function sync() { proc.running = true; }

    Component.onCompleted: root.sync()
}
