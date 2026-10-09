// Shared window chrome: the bar's animated accent border, reused by the
// dialogue panels (Settings / Themer / SysMonitor / …) so they animate like the
// bar. `animated` honours the shared `theme.border_animation` + UI-animations
// switches; `periodMs` follows the real Hyprland animation speed when known.
pragma Singleton

import QtQuick
import Quickshell
import "../config"

Singleton {
    id: root

    readonly property bool animated: BarConfig.theme.border_animation !== false && Config.uiAnimations

    readonly property int periodMs: {
        if (HyprAnim.periodMs > 0)
            return HyprAnim.periodMs;
        const mode = BarConfig.animations.mode || "high";
        if (mode === "custom")
            return Math.max(200, Math.round(4000 / Math.max(1, BarConfig.animations.speed || 15)));
        return mode === "low" ? 3200 : 1400;
    }
}
