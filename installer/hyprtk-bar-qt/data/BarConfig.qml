// The Qt bar's config blocks (module options, font, animations and the
// `monitors` selector). Read from the Qt bar's own config
// (~/.config/hyprtk-bar-qt/config.json), separate from the GTK bar's.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    property var cfg: ({})

    FileView {
        id: cfgFile
        path: root.home + "/.config/hyprtk-bar-qt/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: root._parse()
        onTextChanged: root._parse()
        onFileChanged: reload()
    }
    function _parse() {
        try {
            root.cfg = JSON.parse(cfgFile.text()) || ({});
        } catch (e) {
            root.cfg = ({});
        }
    }

    function block(key) {
        const b = root.cfg[key];
        return (b && typeof b === "object") ? b : ({});
    }
    function top(key, fallback) {
        const v = root.cfg[key];
        return (v === undefined || v === null) ? fallback : v;
    }

    // ── top-level bar geometry (the Qt bar's own config) ───────────────
    readonly property string barPosition: top("position", "top")
    readonly property int barHeight: top("height", 38)
    readonly property int gapIn: top("gap_in", 0)
    readonly property int gapOut: top("gap_out", 0)
    readonly property int radius: top("radius", 12)
    readonly property int borderWidth: top("border_width", 2)
    readonly property var barWidth: top("width", "75%")
    readonly property string barAlign: top("align", "center")

    readonly property var layoutLeft: block("layout").left || []
    readonly property var layoutCenter: block("layout").center || []
    readonly property var layoutRight: block("layout").right || []

    readonly property var theme: block("theme")
    readonly property var workspaces: block("workspaces")
    readonly property var clock: block("clock")
    readonly property var media: block("media")
    readonly property var tray: block("tray")
    readonly property var windowBlock: block("window")
    readonly property var center: block("center")
    readonly property var updates: block("updates")
    readonly property var sysmon: block("sysmon")
    readonly property var quicklinks: block("quicklinks")
    readonly property var themer: block("themer")
    readonly property var quicksettings: block("quicksettings")
    readonly property var notifications: block("notifications")
    readonly property var arcmenu: block("arcmenu")
    readonly property var font: block("font")
    readonly property var animations: block("animations")
    readonly property var monitors: root.cfg.monitors !== undefined ? root.cfg.monitors : "primary"

    // font.family "" = follow the Qt bar's own font.
    function fontFamily(fallback) {
        const f = root.font.family;
        return (typeof f === "string" && f.length > 0) ? f : fallback;
    }
    function fontSize(fallback) {
        const s = root.font.size;
        return (typeof s === "number" && s > 0) ? s : fallback;
    }

    // Module-icon pixel size: `font.icon_size` verbatim when > 0, else scaled
    // from the base font (mirrors the GTK bar's icon_size_for()).
    function iconSize(fontSize, fallback) {
        const s = root.font.icon_size;
        if (typeof s === "number" && s > 0)
            return Math.max(8, Math.round(s));
        const f = (typeof fontSize === "number" && fontSize > 0) ? fontSize : (fallback || 12);
        return Math.max(8, Math.round(f * 1.25));
    }

    // Nerd Font family for every bar glyph (matches the GTK bar's GLYPH_FONT),
    // overridable via quicklinks.glyph_font.
    readonly property string glyphFont: {
        const f = root.quicklinks.glyph_font;
        return (typeof f === "string" && f.length > 0) ? f : "Symbols Nerd Font";
    }
}
