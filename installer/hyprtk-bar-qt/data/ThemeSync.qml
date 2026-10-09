// Applies a bar theme — writes the nested `theme` block + the Qt overrides and
// re-links the rofi variant so rofi always matches the bar.
//
// Mirrors the GTK bar (app.py::_sync_rofi_variant): changing `theme.source` /
// `theme.theme_name` must also update `~/.config/rofi/variant.rasi` via
// sync-rofi-theme.sh. Every theme change (Themer / Settings) goes through
// `apply()` so the two config representations and rofi stay in lock-step.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/barsettings.py").toString().replace("file://", "")
    readonly property string syncScript:
        root.home + "/.local/share/hyprtk-bar-qt/scripts/sync-rofi-theme.sh"

    // source: "pywal" | "imported" | "manual" ("" follows pywal); colours optional.
    function apply(source, name, background, foreground, accent) {
        const src = source || "";
        // Live Qt overrides — Theme.qml reads these properties directly (its
        // config FileView does not watch the file), so this is what re-themes
        // the bar immediately.
        Config.themeSource = src;
        Config.themeName = name || "";
        Config.themeBackground = background || "";
        Config.themeForeground = foreground || "";
        Config.themeAccent = accent || "";
        // Persist BOTH representations in one atomic write (barsettings does a
        // whole-file read-modify-write, so two separate writers — Config.save()
        // and a nested patch — race and clobber each other):
        //   • top-level `themeSource`/`themeName`/… = the Qt overrides;
        //   • nested `theme` block = what sync-rofi-theme.sh reads.
        const patch = {
            themeSource: src,
            themeName: name || "",
            themeBackground: background || "",
            themeForeground: foreground || "",
            themeAccent: accent || "",
            theme: {
                source: src || "pywal",
                theme_name: name || "",
                background: background || "",
                foreground: foreground || "",
                accent: accent || ""
            }
        };
        setProc.command = ["python3", root.backend, "set", "--json", JSON.stringify(patch)];
        setProc.running = true;
    }

    // Re-link rofi from the current config (start-up + after every theme write).
    function syncRofi() { syncProc.running = true; }

    Process { id: setProc; onExited: (code, status) => root.syncRofi() }
    Process { id: syncProc; command: ["bash", root.syncScript] }

    Component.onCompleted: root.syncRofi()
}
