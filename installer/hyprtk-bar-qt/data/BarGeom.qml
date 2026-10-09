// Bar geometry (width + screen-edge insets), shared by the bar and the popups
// so panels can be positioned within the bar's horizontal extent.
pragma Singleton

import QtQuick
import Quickshell
import "."

Singleton {
    id: root

    // Parsed bar width in px for a given screen width.
    function width(screenW) {
        const w = BarConfig.barWidth;
        if (typeof w === "string" && w.endsWith("%")) {
            const pct = parseFloat(w);
            return Math.round(screenW * Math.max(0, Math.min(pct, 100)) / 100);
        }
        const px = parseInt(w);
        return isNaN(px) ? screenW : px;
    }

    // Left/right margins for the bar pill on a screen of the given width.
    function insets(screenW) {
        const avail = screenW - BarConfig.gapOut * 2;
        const w = Math.max(120, Math.min(root.width(screenW), avail));
        const leftover = avail - w;
        if (BarConfig.barAlign === "left")
            return { left: BarConfig.gapOut, right: BarConfig.gapOut + leftover };
        if (BarConfig.barAlign === "right")
            return { left: BarConfig.gapOut + leftover, right: BarConfig.gapOut };
        const half = Math.round(leftover / 2);
        return { left: BarConfig.gapOut + half, right: BarConfig.gapOut + (leftover - half) };
    }
}
