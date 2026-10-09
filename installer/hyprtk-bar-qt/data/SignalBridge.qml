// Signal bridge: maps the dotfiles' bar keybinds to this bar's surfaces.
//
// The GTK toggle scripts send SIGUSR1 (start menu), SIGUSR2 (arc menu) and
// SIGHUP (clipboard) to the PID in the shared lock file; signal_bridge.py
// claims that lock and streams the matching command here.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../state"

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/signal_bridge.py").toString().replace("file://", "")

    Process {
        id: proc
        running: true
        command: ["python3", "-u", root.backend]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const c = JSON.parse(line).cmd;
                    if (c === "menu")
                        UiState.startMenuOpen = !UiState.startMenuOpen;
                    else if (c === "arc")
                        UiState.arcMenuOpen = !UiState.arcMenuOpen;
                    else if (c === "clipboard")
                        UiState.clipboardOpen = !UiState.clipboardOpen;
                } catch (e) {}
            }
        }
    }
}
