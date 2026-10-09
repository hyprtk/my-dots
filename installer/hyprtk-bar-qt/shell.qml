// hyprtk-bar-qt — Quickshell entry point.
//
// QML presentation layer of the Qt rewrite. One layer-shell PanelWindow per
// screen, each rendering Bar.qml, plus the surfaces (quick settings, settings,
// arc menu, bar menu, start menu, themer). Heavy logic lives in the Python
// backend (backend/hyprtk_bar_qt) and is streamed in over Quickshell Process.
import Quickshell
import Quickshell.Io
import QtQuick
import "bar"
import "surface"
import "config"
import "state"
import "data"

ShellRoot {
    id: shell

    // Instantiate the keybind signal bridge (menu/arc/clipboard toggles) and the
    // theme writer (keeps the rofi variant in sync with `theme.source`).
    readonly property var signalBridge: SignalBridge
    readonly property var themeSync: ThemeSync
    readonly property var lockSync: LockSync

    // Screens that should show the bar, per the `monitors` selector in the Qt
    // bar's config ("primary" | "all" | ["CONNECTOR", ...]).
    function _screens() {
        const screens = Quickshell.screens;
        const m = BarConfig.monitors;
        if (Array.isArray(m))
            return screens.filter(s => m.indexOf(s.name) >= 0);
        if (m === "all")
            return screens;
        return screens.length ? [screens[0]] : [];
    }

    // Bar width / insets are shared with the popups (data/BarGeom.qml).
    function _insets(screenW) {
        return BarGeom.insets(screenW);
    }

    Variants {
        model: shell._screens()

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            readonly property var insets: shell._insets(modelData.width)

            anchors.top: BarConfig.barPosition === "top"
            anchors.bottom: BarConfig.barPosition === "bottom"
            anchors.left: true
            anchors.right: true
            margins.top: BarConfig.barPosition === "top" ? BarConfig.gapOut : 0
            margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.gapOut : 0
            margins.left: panel.insets.left
            margins.right: panel.insets.right
            implicitHeight: BarConfig.barHeight
            // Reserve the bar plus its windows-side (gap_in) and edge-side
            // (gap_out) breathing space, matching the GTK surface height.
            exclusiveZone: BarConfig.barHeight + BarConfig.gapIn + BarConfig.gapOut
            color: "transparent"

            Bar {
                anchors.fill: parent
            }
        }
    }

    QuickSettings {}
    Settings {}
    ArcMenu {}
    BarMenu {}
    StartMenu {}
    Themer {}
    SysMonitor {}
    NotificationCenter {}
    Clipboard {}
    About {}
    DesktopWidgets {}

    Loader {
        active: Quickshell.env("HYPRTK_BAR_QT_NOTIFICATIONS") !== "0"
        source: "surface/Notifications.qml"
    }

    IpcHandler {
        target: "shell"
        function reload() { Quickshell.reload(true); }
    }
}
