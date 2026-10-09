// The hyprtk theme, resolved live from (in order of precedence):
//   1. hyprtk-bar-qt's own overrides (config/Config)
//   2. the Qt bar config's theme block (~/.config/hyprtk-bar-qt/config.json)
//   3. live pywal colours
//
// Singleton: import "../theme" anywhere.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""

    function num(v, fallback) {
        return (typeof v === "number" && isFinite(v)) ? v : fallback;
    }
    function strKey(obj, key, fallback) {
        const v = obj ? obj[key] : undefined;
        return (typeof v === "string" && v.trim().length > 0) ? v : fallback;
    }
    function pick(override, fallback) {
        return (typeof override === "string" && override.trim().length > 0) ? override : fallback;
    }

    // ── pywal live palette ─────────────────────────────────────────────
    property var wal: ({})
    FileView {
        id: walFile
        path: root.home + "/.cache/wal/colors.json"
        watchChanges: true
        printErrors: false
        onLoaded: root._parseWal()
        onTextChanged: root._parseWal()
        onFileChanged: reload()
    }
    function _parseWal() {
        try {
            root.wal = JSON.parse(walFile.text()) || ({});
        } catch (e) {
            root.wal = ({});
        }
    }

    // ── Qt bar config (theme block + opacity) ──────────────────────────
    property var config: ({})
    FileView {
        id: cfgFile
        path: root.home + "/.config/hyprtk-bar-qt/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: root._parseCfg()
        onTextChanged: root._parseCfg()
        onFileChanged: reload()
    }
    function _parseCfg() {
        try {
            root.config = JSON.parse(cfgFile.text()) || ({});
        } catch (e) {
            root.config = ({});
        }
    }

    readonly property var colors: root.wal.colors || ({})
    readonly property var special: root.wal.special || ({})
    readonly property var theme: root.config.theme || ({})
    // `theme.source` wins; the legacy `use_pywal` flag seeds the default (as in
    // the GTK bar's theme.py), so the setting is not dead.
    readonly property string source: root.pick(Config.themeSource,
        root.theme.source || (root.config.use_pywal === false ? "manual" : "pywal"))

    readonly property color background: root.pick(Config.themeBackground,
        root.source === "pywal"
            ? root.strKey(root.special, "background", "#1e1e2e")
            : root.strKey(root.theme, "background", "#1e1e2e"))
    readonly property color foreground: root.pick(Config.themeForeground,
        root.source === "pywal"
            ? root.strKey(root.special, "foreground", "#e5e7eb")
            : root.strKey(root.theme, "foreground", "#e5e7eb"))
    readonly property color accent: root.pick(Config.themeAccent,
        root.source === "pywal"
            ? (root.colors.color5 || root.colors.color4 || "#c084fc")
            : root.strKey(root.theme, "accent", "#c084fc"))
    readonly property color accent2: root.colors.color6 || "#22d3ee"
    readonly property color dim: root.colors.color8 || "#6b7280"
    readonly property color err: root.colors.color1 || "#f38ba8"
    readonly property color warn: root.colors.color3 || "#f9e2af"
    readonly property real opacity: root.num(root.config.opacity, 0.92)
    readonly property string themeName: root.pick(Config.themeName, root.theme.theme_name || "")

    readonly property string fontFamily: root.pick(Config.fontFamily, "Noto Sans")
    readonly property int fontSize: Config.fontSize > 0 ? Config.fontSize : 12

    // A translucent variant of a colour (alpha 0..1), for surface tints.
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // A pywal palette colour by index (1..16), falling back when absent. Used
    // by the on-demand colour pickers to widen the surface beyond the named tokens.
    function walColor(n, fallback) {
        const c = root.colors ? root.colors["color" + n] : undefined;
        return (typeof c === "string" && c.length > 0) ? c : fallback;
    }
}
