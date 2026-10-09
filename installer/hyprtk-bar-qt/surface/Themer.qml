// Themer — centred layer-shell panel with a sidebar of theming pages: Wallpaper
// (thumbnail picker), Pywal, Rofi, Bar Themes (9 shipped), Matuwall, Lock
// Screen, Icons, SDDM & GRUB, and Import (waybar themes from disk).
//
// Script-driven actions call the same hyprtk scripts as the GTK bar, including
// the Matuwall TOML editor.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"
import "../state"
import "../components"
import "../data"

PanelWindow {
    id: win

    visible: UiState.themerOpen
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 760
    implicitHeight: 620

    // Open under the wallpaper/themer glyph on its monitor (registered by the
    // trigger), else the focused monitor.
    property var targetScreen: null
    screen: Screens.byName(BarAnchors.themerScreen) || targetScreen

    readonly property real screenW: win.screen ? win.screen.width : 0
    readonly property var insets: BarGeom.insets(win.screenW)
    // Left edge under the wallpaper/themer glyph, clamped inside the bar's
    // extent so the panel never spills past the bar/screen boundary.
    readonly property real leftMargin: Math.max(
        win.insets.left,
        Math.min(win.insets.left + Math.max(0, BarAnchors.themerX),
                 win.screenW - win.insets.right - win.implicitWidth))

    anchors.top: BarConfig.barPosition === "top"
    anchors.bottom: BarConfig.barPosition === "bottom"
    anchors.left: true
    margins.top: BarConfig.barPosition === "top" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.left: win.leftMargin

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string base: Qt.resolvedUrl("../backend/hyprtk_bar_qt/").toString().replace("file://", "")
    readonly property string scripts: win.home + "/.local/share/hyprtk-bar-qt/scripts"

    readonly property var pages: [
        { key: "wallpaper", glyph: "\uf03e", label: "Wallpaper" },
        { key: "pywal", glyph: "\uf043", label: "Pywal" },
        { key: "rofi", glyph: "\uf009", label: "Rofi" },
        { key: "bar", glyph: "\uf1fc", label: "Bar Themes" },
        { key: "matuwall", glyph: "\uf1c5", label: "Matuwall" },
        { key: "swaylock", glyph: "\uf023", label: "Lock Screen" },
        { key: "icons", glyph: "\uf02d", label: "Icons" },
        { key: "sddm", glyph: "\uf005", label: "SDDM & GRUB" },
        { key: "import", glyph: "\uf019", label: "Import" }
    ]
    property int page: 0

    property var themes: []
    property var importable: []
    property var images: []
    property string currentWall: ""
    // Bumped whenever the current wallpaper is (re)read, to bust QML's Image
    // cache — ~/.cache/current-wallpaper.png keeps the same URL while its
    // contents change, so the preview would otherwise stay stale.
    property int currentWallVersion: 0
    property var rofiVariants: []
    property string rofiActive: ""
    property string statusMsg: ""
    property string importPath: ""
    property string lockConf: ""
    property string iconHex: "#2196F3"
    property var mwConfig: ({})
    property var mwSections: []

    // wallpaper selection (Apply Selected / Random)
    property string selectedWall: ""
    property string wallQuery: ""
    // pywal palette + saved schemes
    property var pywalColors: []
    property var pywalNames: []
    property var pywalSpecial: ({})
    property var pywalSchemes: []
    property string pywalInspect: ""
    property string pywalDir: ""
    // papirus folder icons
    property var iconPresets: []
    property var iconPreview: []
    property string iconCurrent: ""
    property var lockItems: []
    property string lockKind: ""
    property string lockPath: ""

    function wallDir() {
        return Config.wallpaperDir.length > 0 ? Config.wallpaperDir : win.home + "/Pictures/Wallpapers";
    }

    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

    onVisibleChanged: {
        win.reveal = visible ? 1 : 0;
        if (!visible)
            return;
        win.targetScreen = Screens.focused();
        win.refreshThemes();
        win.refreshImportable();
        win.refreshWallpapers();
        win.refreshRofi();
        win.refreshPywal();
        win.refreshSchemes();
        win.refreshIcons();
        win.refreshLock();
        currentProc.running = true;
        lockFile.reload();
        mwGetProc.running = true;
        sddmFind.running = true;
    }

    // Resolve the SDDM/GRUB updater from the live tree (no hardcoded path).
    property string sddmScript: ""
    Process {
        id: sddmFind
        command: ["bash", "-lc",
            'for p in "$HOME/hyprtk/configs/sddm/update.sh" "$HOME"/hyprtk/distro/*/configs/sddm/update.sh; do [ -f "$p" ] && { echo "$p"; break; }; done']
        stdout: SplitParser { onRead: line => { win.sddmScript = line.trim(); } }
    }

    function toast(msg) {
        win.statusMsg = msg;
        statusTimer.restart();
    }
    function refreshThemes() { if (!themeProc.running) themeProc.running = true; }
    function refreshImportable() { if (!installedProc.running) installedProc.running = true; }
    function refreshWallpapers() {
        scanProc.command = ["python3", win.base + "wallpapers.py", "scan", win.wallDir()];
        scanProc.running = true;
    }
    function refreshRofi() {
        win.rofiVariants = [];
        win.rofiActive = "";
        rofiProc.running = true;
    }

    Process {
        id: themeProc
        command: ["python3", win.base + "themes.py", "list"]
        stdout: SplitParser {
            onRead: line => {
                try { win.themes = JSON.parse(line).themes || []; } catch (e) { win.themes = []; }
            }
        }
    }
    Process {
        id: installedProc
        command: ["python3", win.base + "themes.py", "installed"]
        stdout: SplitParser {
            onRead: line => {
                try { win.importable = JSON.parse(line).installed || []; } catch (e) { win.importable = []; }
            }
        }
    }
    Process {
        id: scanProc
        stdout: SplitParser {
            onRead: line => {
                try { win.images = JSON.parse(line).images || []; } catch (e) { win.images = []; }
            }
        }
    }
    Process {
        id: currentProc
        command: ["python3", win.base + "wallpapers.py", "current"]
        stdout: SplitParser {
            onRead: line => {
                try { win.currentWall = JSON.parse(line).current || ""; } catch (e) { win.currentWall = ""; }
                win.currentWallVersion++;
            }
        }
    }
    Process {
        id: applyProc
        onExited: (code, status) => {
            win.toast(code === 0 ? "Applying wallpaper\u2026" : "Could not apply wallpaper");
            currentProc.running = true;
        }
    }
    Process {
        id: importProc
        onExited: (code, status) => {
            win.toast(code === 0 ? "Theme imported" : "Import failed");
            win.refreshThemes();
            win.refreshImportable();
        }
    }
    // rofi folder picker for the Import path field.
    Process {
        id: pickProc
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim();
                if (p) {
                    win.importPath = p;
                    importField.text = p;
                }
            }
        }
        onExited: (code, status) => { if (code === 0) win.toast("Folder selected"); }
    }
    Process {
        id: removeProc
        onExited: (code, status) => { win.refreshThemes(); win.refreshImportable(); }
    }
    Process {
        id: rofiProc
        command: ["bash", "-c",
            "printf 'LINK=%s\\n' \"$(readlink ~/.config/rofi/variant.rasi 2>/dev/null)\"; " +
            "ls -1 ~/.local/share/hyprtk-bar-qt/scripts/rofi/variants/*.rasi 2>/dev/null || " +
            "ls -1 ~/.config/rofi/variants/*.rasi 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("LINK=")) {
                    const p = line.substring(5);
                    win.rofiActive = p.length ? p.split("/").pop().replace(/\.rasi$/, "") : "";
                } else if (line.endsWith(".rasi")) {
                    win.rofiVariants = win.rofiVariants.concat([{ name: line.split("/").pop().replace(/\.rasi$/, ""), path: line }]);
                }
            }
        }
    }
    FileView {
        id: lockFile
        path: win.home + "/.cache/wal/hyprlock-colors.conf"
        watchChanges: true
        printErrors: false
        onLoaded: win.lockConf = lockFile.text()
        onTextChanged: win.lockConf = lockFile.text()
        onFileChanged: reload()
    }
    Timer { id: statusTimer; interval: 3000; onTriggered: win.statusMsg = "" }

    // ── pywal palette + saved schemes ──────────────────────────────────
    Process {
        id: pywalProc
        command: ["python3", win.base + "pywal.py", "palette"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    win.pywalColors = o.colors || [];
                    win.pywalNames = o.names || [];
                    win.pywalSpecial = ({ background: o.background, foreground: o.foreground, cursor: o.cursor });
                } catch (e) {}
            }
        }
    }
    Process {
        id: schemesProc
        command: ["python3", win.base + "pywal.py", "schemes"]
        stdout: SplitParser {
            onRead: line => {
                try { win.pywalSchemes = JSON.parse(line).schemes || []; } catch (e) { win.pywalSchemes = []; }
            }
        }
    }
    Process { id: walApplyProc; onExited: (code, status) => { pywalRefresh.restart(); } }
    Process {
        id: walRerunProc
        property string chosen: ""
        stdout: SplitParser {
            onRead: line => { try { walRerunProc.chosen = JSON.parse(line).path || ""; } catch (e) {} }
        }
        onExited: (code, status) => {
            win.toast(code === 0
                ? ("Wallpaper: " + walRerunProc.chosen.split("/").pop())
                : "No wallpapers found");
            if (code === 0 && walRerunProc.chosen.length)
                win.selectedWall = walRerunProc.chosen;
            currentProc.running = true;
            pywalRefresh.restart();
        }
    }
    Timer { id: pywalRefresh; interval: 2500; onTriggered: { win.refreshPywal(); win.refreshSchemes(); } }

    // ── papirus folder icons ───────────────────────────────────────────
    Process {
        id: iconProc
        command: ["python3", win.base + "icons.py", "current"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    win.iconCurrent = o.color || "";
                    win.iconPreview = o.preview || [];
                } catch (e) {}
            }
        }
    }
    Process {
        id: iconPresetsProc
        command: ["python3", win.base + "icons.py", "presets"]
        stdout: SplitParser {
            onRead: line => {
                try { win.iconPresets = JSON.parse(line).presets || []; } catch (e) { win.iconPresets = []; }
            }
        }
    }
    Process { id: iconApplyProc; onExited: (code, status) => { iconProc.running = true; win.toast(code === 0 ? "Folder colour applied" : "papirus-folders not found"); } }

    // ── lock-screen settings ───────────────────────────────────────────
    Process {
        id: lockReadProc
        command: ["python3", win.base + "lock.py", "read"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    win.lockItems = o.items || [];
                    win.lockKind = o.kind || "";
                    win.lockPath = o.path || "";
                } catch (e) {}
            }
        }
    }
    Process { id: lockSetProc; onExited: (code, status) => { lockReadProc.running = true; win.toast(code === 0 ? "Lock setting saved" : "Could not save"); } }
    // Re-apply: run pywal, then write the palette into the active lock config.
    Process {
        id: lockRerunProc
        command: ["bash", "-lc", "wal -R -q; python3 " + win.base + "lock.py sync-pywal"]
        onExited: (code, status) => { lockFile.reload(); lockRefresh.restart(); }
    }
    Timer { id: lockRefresh; interval: 2500; onTriggered: win.refreshLock() }

    function applyWallpaper(path) {
        applyProc.command = ["python3", win.base + "wallpapers.py", "apply", path];
        applyProc.running = true;
    }
    // Persist Qt-config edits immediately (debounced) so closing the Themer
    // without pressing Save does not lose them.
    Timer { id: cfgSaveTimer; interval: 400; onTriggered: Config.save() }
    function saveCfgSoon() { cfgSaveTimer.restart(); }

    // Keep the desktop widgets' opacity in step with the bar opacity.
    property real pendingWidgetOpacity: 0
    Timer {
        id: widgetOpTimer
        interval: 200
        onTriggered: {
            widgetOpProc.command = ["python3", win.base + "widgets_layout.py",
                "set-opacity", "--value", String(win.pendingWidgetOpacity)];
            widgetOpProc.running = true;
        }
    }
    Process { id: widgetOpProc }
    function syncWidgetOpacity(v) {
        win.pendingWidgetOpacity = v;
        widgetOpTimer.restart();
    }

    function applyTheme(t) {
        // Writes the nested theme block + Qt overrides and re-links rofi.
        ThemeSync.apply("manual", t.name, t.palette.background, t.palette.foreground, t.palette.accent);
        win.toast("Theme: " + t.name);
        rofiRefresh.restart();
    }
    function clearOverrides() {
        // "Follow pywal": drop the overrides and let the pywal variant track live.
        ThemeSync.apply("pywal", "", "", "", "");
        rofiRefresh.restart();
    }
    function doImport(path) {
        if (!path) { win.toast("Enter a theme path"); return; }
        importProc.command = ["python3", win.base + "themes.py", "import", path];
        importProc.running = true;
    }
    function browseImport() {
        pickProc.command = ["python3", win.base + "pickdir.py", win.importPath || ""];
        pickProc.running = true;
    }
    function doRemove(name) {
        removeProc.command = ["python3", win.base + "themes.py", "remove", name];
        removeProc.running = true;
    }
    function applyRofi(path) {
        Quickshell.execDetached(["bash", "-c",
            "ln -sf '" + path + "' ~/.config/rofi/variant.rasi && bash '" + win.scripts + "/sync-rofi-theme.sh'"]);
        win.toast("Rofi variant: " + path.split("/").pop().replace(/\.rasi$/, ""));
        rofiRefresh.restart();
    }
    function regenRofi() {
        Quickshell.execDetached(["bash", win.scripts + "/sync-rofi-theme.sh"]);
        win.toast("Regenerating rofi variant\u2026");
        rofiRefresh.restart();
    }
    function refreshPywal() { if (!pywalProc.running) pywalProc.running = true; }
    function refreshSchemes() { if (!schemesProc.running) schemesProc.running = true; }
    function refreshIcons() {
        if (!iconProc.running) iconProc.running = true;
        if (!iconPresetsProc.running) iconPresetsProc.running = true;
    }
    function applyScheme(path) {
        walApplyProc.command = ["python3", win.base + "pywal.py", "apply-scheme", path];
        walApplyProc.running = true;
        win.toast("Applied scheme: " + path.split("/").pop());
    }
    // Pick a random wallpaper from the wall dir and apply it: sets the wallpaper
    // and regenerates every pywal-template colour in one shot.
    function rerunWal() {
        walRerunProc.chosen = "";
        walRerunProc.command = ["python3", win.base + "wallpapers.py", "random",
            win.pywalDir.length ? win.pywalDir : win.wallDir()];
        walRerunProc.running = true;
    }
    function applySelectedWall() {
        if (!win.selectedWall) { win.toast("Select a wallpaper first"); return; }
        win.applyWallpaper(win.selectedWall);
    }
    function applyRandomWall() {
        if (!win.images.length) { win.toast("No wallpapers to choose from"); return; }
        const p = win.images[Math.floor(Math.random() * win.images.length)];
        win.selectedWall = p.path || p;
        win.applyWallpaper(p.path || p);
    }
    function filteredWalls() {
        const q = win.wallQuery.trim().toLowerCase();
        if (!q)
            return win.images;
        return win.images.filter(it => (it.path || it).toLowerCase().includes(q));
    }
    function applyIconPreset(color) {
        iconApplyProc.command = ["python3", win.base + "icons.py", "apply-preset", color];
        iconApplyProc.running = true;
    }
    function applyIconHex() {
        iconApplyProc.command = ["python3", win.base + "icons.py", "apply-hex", win.iconHex];
        iconApplyProc.running = true;
    }
    function iconAuto() {
        iconApplyProc.command = ["python3", win.base + "icons.py", "auto"];
        iconApplyProc.running = true;
    }
    function refreshLock() { if (!lockReadProc.running) lockReadProc.running = true; }
    function reapplyLock() {
        // runs wal -R then lock.py sync-pywal (see lockRerunProc)
        lockRerunProc.running = true;
        win.toast("Re-applying pywal theme");
    }
    function setLock(key, value) {
        lockSetProc.command = ["python3", win.base + "lock.py", "set", "--key", key, "--value", value];
        lockSetProc.running = true;
    }

    Timer { id: rofiRefresh; interval: 800; onTriggered: win.refreshRofi() }

    // ── matuwall ───────────────────────────────────────────────────────
    Process {
        id: mwGetProc
        command: ["python3", win.base + "matuwall.py", "get"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    win.mwConfig = o.config || ({});
                    win.mwSections = o.sections || [];
                } catch (e) {}
            }
        }
    }
    Process {
        id: mwSetProc
        onExited: (code, status) => win.toast(code === 0 ? "Matuwall config saved" : "Save failed")
    }
    function mwValue(section, key) {
        let node = win.mwConfig;
        for (const p of section.split(".")) {
            if (!node || typeof node !== "object")
                return undefined;
            node = node[p];
        }
        return node ? node[key] : undefined;
    }
    function mwSet(section, key, value) {
        const c = JSON.parse(JSON.stringify(win.mwConfig || ({})));
        let node = c;
        for (const p of section.split("."))
            node = (node[p] = node[p] || ({}));
        node[key] = value;
        win.mwConfig = c;
    }
    function mwIdx(choices, v) {
        const i = (choices || []).indexOf(v);
        return i < 0 ? 0 : i;
    }
    function mwSave() {
        mwSetProc.command = ["python3", win.base + "matuwall.py", "set", "--json", JSON.stringify(win.mwConfig || ({}))];
        mwSetProc.running = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.95, Theme.opacity))
        opacity: win.reveal
        transform: Translate { y: (1 - win.reveal) * -8 }
    }

    IpcHandler {
        target: "themer"
        function toggle() { UiState.themerOpen = !UiState.themerOpen; }
        function open() { UiState.themerOpen = true; }
        function close() { UiState.themerOpen = false; }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        opacity: win.reveal
        transform: Translate { y: (1 - win.reveal) * -8 }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 150
            topLeftRadius: 14
            bottomLeftRadius: 14
            color: Theme.alpha(Theme.background, 0.6)
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 3
                Repeater {
                    model: win.pages
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: win.page === index
                            ? Theme.alpha(Theme.accent, 0.85)
                            : (sbHover.hovered ? Theme.alpha(Theme.accent2, 0.15) : "transparent")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8
                            Text { text: modelData.glyph; color: win.page === index ? "#000000" : Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
                            Text { text: modelData.label; color: win.page === index ? "#000000" : Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true }
                        }
                        HoverHandler { id: sbHover }
                        TapHandler { onTapped: win.page = index }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text { text: win.pages[win.page].label; color: Theme.accent; font.bold: true; font.pixelSize: 15; Layout.fillWidth: true }
                Text { text: "\u00d7"; color: Theme.dim; font.pixelSize: 18; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: UiState.themerOpen = false } }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                // Wallpaper ────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    RowLayout {
                        spacing: 10
                        Image {
                            source: {
                                if (win.selectedWall.length)
                                    return "file://" + win.selectedWall;
                                return win.currentWall.length
                                    ? ("file://" + win.currentWall + "?v=" + win.currentWallVersion)
                                    : "";
                            }
                            sourceSize.width: 200
                            sourceSize.height: 112
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 112
                            fillMode: Image.PreserveAspectCrop
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Text { text: "Wallpaper folder"; color: Theme.dim; font.pixelSize: 11 }
                            TTextField {
                                Layout.fillWidth: true
                                text: win.wallDir()
                                color: Theme.foreground
                                onEditingFinished: { Config.wallpaperDir = text; Config.save(); win.refreshWallpapers(); }
                            }
                            RowLayout {
                                spacing: 6
                                TButton { text: "Rescan"; onClicked: { win.refreshWallpapers(); currentProc.running = true; win.toast("Rescanning\u2026"); } }
                                TButton { text: "Apply Selected"; onClicked: win.applySelectedWall() }
                                TButton { text: "Random"; onClicked: win.applyRandomWall() }
                                Item { Layout.fillWidth: true }
                            }
                            TTextField {
                                Layout.fillWidth: true
                                placeholderText: "Search wallpapers\u2026"
                                color: Theme.foreground
                                onTextChanged: win.wallQuery = text
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: win.filteredWalls().length === 0
                        text: "No images in this folder"
                        color: Theme.dim
                        font.pixelSize: 11
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: grid.implicitHeight
                        clip: true
                        visible: win.filteredWalls().length > 0
                        GridLayout {
                            id: grid
                            width: parent.width
                            columns: 4
                            columnSpacing: 8
                            rowSpacing: 8
                            Repeater {
                                model: win.filteredWalls()
                                delegate: Rectangle {
                                    id: thumb
                                    required property var modelData
                                    readonly property string wpath: modelData.path || modelData
                                    readonly property string wthumb: modelData.thumb || modelData.path || modelData
                                    readonly property bool sel: win.selectedWall === thumb.wpath
                                    Layout.fillWidth: true
                                    implicitHeight: 78
                                    radius: 6
                                    color: Theme.alpha(Theme.background, 0.5)
                                    border.width: thumb.sel ? 2 : 1
                                    border.color: thumb.sel ? Theme.accent
                                        : (thumbHover.hovered ? Theme.accent : Theme.alpha(Theme.accent2, 0.2))
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: "file://" + thumb.wthumb
                                        sourceSize.width: 160
                                        sourceSize.height: 72
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }
                                    HoverHandler { id: thumbHover }
                                    TapHandler { onTapped: win.selectedWall = thumb.wpath }
                                    TapHandler { onDoubleTapped: win.applyWallpaper(thumb.wpath) }
                                }
                            }
                        }
                    }
                }

                // Pywal ────────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    Text { text: "Live pywal palette (16 colours)"; color: Theme.dim; font.pixelSize: 11 }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 8
                        columnSpacing: 6
                        rowSpacing: 6
                        Repeater {
                            model: win.pywalColors
                            delegate: Rectangle {
                                id: sw
                                required property var modelData
                                required property int index
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 8
                                color: modelData || Theme.background
                                border.width: win.pywalInspect === ("color" + sw.index) ? 2 : 1
                                border.color: win.pywalInspect === ("color" + sw.index) ? Theme.accent : Theme.alpha(Theme.foreground, 0.3)
                                HoverHandler { id: swHover }
                                TapHandler { onTapped: win.pywalInspect = "color" + sw.index }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.pywalInspect.length
                            ? (win.pywalInspect + ": " + win.pywalColors[parseInt(win.pywalInspect.slice(5))] + "  (" + (win.pywalNames[parseInt(win.pywalInspect.slice(5))] || "") + ")")
                            : "Click a colour to inspect"
                        color: Theme.foreground
                        font.pixelSize: 11
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "Background"; color: Theme.dim; font.pixelSize: 10 }
                        Rectangle { width: 18; height: 18; radius: 4; color: win.pywalSpecial.background || Theme.background; border.color: Theme.alpha(Theme.foreground, 0.3); border.width: 1 }
                        Text { text: "Foreground"; color: Theme.dim; font.pixelSize: 10 }
                        Rectangle { width: 18; height: 18; radius: 4; color: win.pywalSpecial.foreground || Theme.foreground; border.color: Theme.alpha(Theme.foreground, 0.3); border.width: 1 }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 6
                        Text { text: "wal dir"; color: Theme.dim; font.pixelSize: 10 }
                        TTextField { Layout.fillWidth: true; placeholderText: win.wallDir(); text: win.pywalDir; color: Theme.foreground; onEditingFinished: win.pywalDir = text }
                        TButton { text: "Random wallpaper"; onClicked: win.rerunWal() }
                        TButton { text: "Refresh"; onClicked: { win.refreshPywal(); win.refreshSchemes(); } }
                    }
                    Text { text: "Saved colour schemes (" + win.pywalSchemes.length + ")"; color: Theme.accent; font.bold: true; font.pixelSize: 11 }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: schemeList.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: schemeList
                            width: parent.width
                            spacing: 3
                            Repeater {
                                model: win.pywalSchemes
                                delegate: Rectangle {
                                    id: sch
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 6
                                    color: schHover.hovered ? Theme.alpha(Theme.accent2, 0.15) : "transparent"
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        text: sch.modelData.name
                                        color: Theme.foreground
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                    HoverHandler { id: schHover }
                                    TapHandler { onTapped: win.applyScheme(sch.modelData.path) }
                                }
                            }
                        }
                    }
                }

                // Rofi ─────────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    Text { text: "Active variant: " + (win.rofiActive.length ? win.rofiActive : "(none)"); color: Theme.foreground; font.pixelSize: 12 }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: rofiList.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: rofiList
                            width: parent.width
                            spacing: 3
                            Repeater {
                                model: win.rofiVariants
                                delegate: Rectangle {
                                    id: rr
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    radius: 6
                                    color: rrHover.hovered ? Theme.alpha(Theme.accent2, 0.15)
                                        : (win.rofiActive === rr.modelData.name ? Theme.alpha(Theme.accent, 0.25) : "transparent")
                                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: rr.modelData.name; color: Theme.foreground; font.pixelSize: 12 }
                                    HoverHandler { id: rrHover }
                                    TapHandler { onTapped: win.applyRofi(rr.modelData.path) }
                                }
                            }
                        }
                    }
                    TButton { text: "Regenerate from Pywal"; onClicked: win.regenRofi() }
                }

                // Bar Themes ────────────────────────────────────────────
                ColumnLayout {
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Active: " + (Theme.themeName.length ? Theme.themeName : "(pywal)"); color: Theme.foreground; Layout.fillWidth: true }
                        TButton { text: "Follow pywal"; onClicked: win.clearOverrides() }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 8
                        columnSpacing: 5
                        rowSpacing: 5
                        Repeater {
                            model: win.pywalColors
                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 5
                                color: modelData || Theme.background
                                border.color: Theme.alpha(Theme.foreground, 0.3); border.width: 1
                            }
                        }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: themeList.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: themeList
                            width: parent.width
                            spacing: 3
                            Repeater {
                                model: win.themes
                                delegate: Rectangle {
                                    id: tr
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 6
                                    color: trHover.hovered ? Theme.alpha(Theme.accent2, 0.15)
                                        : (Theme.themeName === tr.modelData.name ? Theme.alpha(Theme.accent, 0.25) : "transparent")
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Text { text: tr.modelData.name; color: Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true }
                                        Repeater {
                                            model: [tr.modelData.palette.background, tr.modelData.palette.foreground, tr.modelData.palette.accent]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: 16; height: 16; radius: 4
                                                color: modelData
                                                border.color: Theme.alpha(Theme.foreground, 0.25); border.width: 1
                                            }
                                        }
                                    }
                                    HoverHandler { id: trHover }
                                    TapHandler { onTapped: win.applyTheme(tr.modelData) }
                                }
                            }
                        }
                    }
                }

                // Matuwall ──────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: mwCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: mwCol
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: win.mwSections
                                delegate: ColumnLayout {
                                    id: mwSec
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: mwSec.modelData.title; color: Theme.accent; font.bold: true; font.pixelSize: 12 }
                                    Repeater {
                                        model: mwSec.modelData.fields
                                        delegate: RowLayout {
                                            id: mwRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: mwRow.modelData.label
                                                color: Theme.foreground
                                                font.pixelSize: 11
                                                Layout.preferredWidth: 170
                                                elide: Text.ElideRight
                                            }
                                            // bool
                                            TCheckBox {
                                                visible: mwRow.modelData.kind === "bool"
                                                checked: win.mwValue(mwSec.modelData.section, mwRow.modelData.key) === true
                                                onToggled: win.mwSet(mwSec.modelData.section, mwRow.modelData.key, checked)
                                            }
                                            // choice
                                            TComboBox {
                                                visible: mwRow.modelData.kind === "choice"
                                                model: mwRow.modelData.choices
                                                currentIndex: win.mwIdx(mwRow.modelData.choices, win.mwValue(mwSec.modelData.section, mwRow.modelData.key))
                                                onActivated: win.mwSet(mwSec.modelData.section, mwRow.modelData.key, model[currentIndex])
                                            }
                                            // str / int / list
                                            TTextField {
                                                visible: mwRow.modelData.kind !== "bool" && mwRow.modelData.kind !== "choice"
                                                Layout.fillWidth: true
                                                color: Theme.foreground
                                                text: {
                                                    const v = win.mwValue(mwSec.modelData.section, mwRow.modelData.key);
                                                    if (v === undefined || v === null)
                                                        return "";
                                                    return Array.isArray(v) ? v.join(", ") : String(v);
                                                }
                                                onEditingFinished: {
                                                    const kind = mwRow.modelData.kind;
                                                    if (kind === "int")
                                                        win.mwSet(mwSec.modelData.section, mwRow.modelData.key, parseInt(text) || 0);
                                                    else if (kind === "list")
                                                        win.mwSet(mwSec.modelData.section, mwRow.modelData.key, text.split(",").map(s => s.trim()).filter(s => s.length));
                                                    else
                                                        win.mwSet(mwSec.modelData.section, mwRow.modelData.key, text);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Writes through the pywal symlink; colour keys stay live."; color: Theme.dim; font.pixelSize: 10; Layout.fillWidth: true }
                        TButton { text: "Save Matuwall"; onClicked: win.mwSave() }
                    }
                }

                // Lock Screen ───────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: win.lockKind.length
                            ? win.lockKind + "  \u00b7  " + win.lockPath
                            : "No lock config found (swaylock or hyprlock)."
                        color: Theme.dim
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 8
                        TButton {
                            text: "Re-apply Pywal Theme"
                            onClicked: win.reapplyLock()
                        }
                        TButton { text: "Reload"; onClicked: win.refreshLock() }
                        Item { Layout.fillWidth: true }
                    }
                    Text { text: "Editable settings (" + win.lockItems.length + ")"; color: Theme.accent; font.bold: true; font.pixelSize: 11 }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: lockCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: lockCol
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: win.lockItems
                                delegate: RowLayout {
                                    id: lk
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        text: lk.modelData.label
                                        color: Theme.foreground
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 170
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        visible: lk.modelData.color
                                        width: 18; height: 18; radius: 4
                                        color: "#" + String(lk.modelData.value).replace(/^#/, "").slice(0, 6)
                                        border.color: Theme.alpha(Theme.foreground, 0.3); border.width: 1
                                    }
                                    TTextField {
                                        Layout.fillWidth: true
                                        text: lk.modelData.value
                                        color: Theme.foreground
                                        onEditingFinished: win.setLock(lk.modelData.key, text)
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Editing writes back to the active lock config; pywal regenerates it on the next wallpaper change."
                        color: Theme.dim
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                    }
                }

                // Icons ─────────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    Text { text: "Current folder colour: " + (win.iconCurrent.length ? win.iconCurrent : "unknown"); color: Theme.foreground; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 10
                        Repeater {
                            model: win.iconPreview
                            delegate: ColumnLayout {
                                required property var modelData
                                spacing: 2
                                Image {
                                    source: modelData.svg.length ? "file://" + modelData.svg : ""
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    Layout.preferredWidth: 40
                                    Layout.preferredHeight: 40
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text { text: modelData.label; color: Theme.dim; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Text { text: "Pywal Auto-Color"; color: Theme.accent; font.bold: true; font.pixelSize: 12; Layout.topMargin: 4 }
                    Text { text: "Matches the Papirus folder colour to pywal colour4."; color: Theme.dim; font.pixelSize: 10 }
                    TButton { text: "Apply pywal colour match"; onClicked: win.iconAuto() }
                    Text { text: "Manual Folder Color"; color: Theme.accent; font.bold: true; font.pixelSize: 12; Layout.topMargin: 4 }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: presetGrid.implicitHeight
                        clip: true
                        GridLayout {
                            id: presetGrid
                            width: parent.width
                            columns: 5
                            columnSpacing: 8
                            rowSpacing: 8
                            Repeater {
                                model: win.iconPresets
                                delegate: Rectangle {
                                    id: pr
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 66
                                    radius: 8
                                    color: prHover.hovered ? Theme.alpha(Theme.accent2, 0.15) : Theme.alpha(Theme.background, 0.4)
                                    border.width: win.iconCurrent === pr.modelData.name ? 2 : 1
                                    border.color: win.iconCurrent === pr.modelData.name ? Theme.accent : Theme.alpha(Theme.accent2, 0.2)
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Image {
                                            source: pr.modelData.svg.length ? "file://" + pr.modelData.svg : ""
                                            sourceSize.width: 30
                                            sourceSize.height: 30
                                            Layout.preferredWidth: 30
                                            Layout.preferredHeight: 30
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text { text: pr.modelData.label; color: Theme.foreground; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                                    }
                                    HoverHandler { id: prHover }
                                    TapHandler { onTapped: win.applyIconPreset(pr.modelData.name) }
                                }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 8
                        TTextField { Layout.preferredWidth: 140; text: win.iconHex; color: Theme.foreground; onEditingFinished: win.iconHex = text }
                        TButton { text: "Apply custom hex"; onClicked: win.applyIconHex() }
                        Item { Layout.fillWidth: true }
                    }
                }

                // SDDM & GRUB ───────────────────────────────────────────
                ColumnLayout {
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: "Update the login screen (SDDM) and bootloader (GRUB) with your current wallpaper. Runs as root via pkexec."
                        color: Theme.foreground
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Image {
                        source: win.currentWall.length
                            ? ("file://" + win.currentWall + "?v=" + win.currentWallVersion)
                            : ""
                        sourceSize.width: 260
                        sourceSize.height: 146
                        Layout.preferredWidth: 260
                        Layout.preferredHeight: 146
                        fillMode: Image.PreserveAspectCrop
                        Layout.alignment: Qt.AlignHCenter
                        visible: win.currentWall.length > 0
                    }
                    RowLayout {
                        spacing: 8
                        TButton {
                            text: "Update SDDM & GRUB Wallpaper"
                            onClicked: {
                                if (win.sddmScript.length) {
                                    Quickshell.execDetached(["pkexec", "bash", win.sddmScript, "-y"]);
                                    win.toast("Updating SDDM & GRUB\u2026");
                                } else {
                                    win.toast("sddm update.sh not found");
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Item { Layout.fillHeight: true }
                }

                // Import ────────────────────────────────────────────────
                RowLayout {
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Text { text: "Importable themes"; color: Theme.dim; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; visible: win.importable.length === 0; text: "None found"; color: Theme.dim; font.pixelSize: 11 }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: impList.implicitHeight
                            clip: true
                            ColumnLayout {
                                id: impList
                                width: parent.width
                                spacing: 3
                                Repeater {
                                    model: win.importable
                                    delegate: Rectangle {
                                        id: ir
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 6
                                        color: irHover.hovered ? Theme.alpha(Theme.accent2, 0.15) : "transparent"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 8
                                            Text { text: ir.modelData.name; color: Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                            Text { text: ir.modelData.path; color: Theme.dim; font.pixelSize: 9; Layout.preferredWidth: 150; elide: Text.ElideMiddle }
                                            TButton { text: "Import"; onClicked: win.doImport(ir.modelData.path) }
                                        }
                                        HoverHandler { id: irHover }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            TTextField {
                                id: importField
                                Layout.fillWidth: true
                                placeholderText: "Path to a theme folder or style.css"
                                color: Theme.foreground
                                onTextChanged: win.importPath = text
                            }
                            TButton { text: "Browse\u2026"; onClicked: win.browseImport() }
                            TButton { text: "Import"; onClicked: win.doImport(win.importPath) }
                        }
                    }
                    ColumnLayout {
                        Layout.preferredWidth: 240
                        Layout.fillHeight: true
                        Text { text: "Imported themes"; color: Theme.dim; font.pixelSize: 11 }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: haveList.implicitHeight
                            clip: true
                            ColumnLayout {
                                id: haveList
                                width: parent.width
                                spacing: 3
                                Repeater {
                                    model: win.themes
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Text { text: modelData.name; color: Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                        TButton { text: "\u2715"; onClicked: win.doRemove(modelData.name) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Bar opacity"; color: Theme.foreground }
                TSlider {
                    Layout.preferredWidth: 160
                    from: 0.2; to: 1.0; stepSize: 0.05
                    value: Config.opacity >= 0 ? Config.opacity : Theme.opacity
                    onMoved: { Config.opacity = value; win.saveCfgSoon(); win.syncWidgetOpacity(value); }
                }
                Text { text: win.statusMsg; color: Theme.accent; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                TButton { text: "Save"; onClicked: Config.save() }
                TButton { text: "Close"; onClicked: UiState.themerOpen = false }
            }
        }
    }

    // Animated accent border drawn ON TOP of the sidebar + content, so it reads
    // the same on every edge (the background's border was covered on the left).
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "transparent"
        border.width: BarConfig.borderWidth
        border.color: Theme.accent
        SequentialAnimation on border.color {
            running: Chrome.animated
            loops: Animation.Infinite
            ColorAnimation { to: Theme.accent2; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
            ColorAnimation { to: Theme.accent; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
        }
        opacity: win.reveal
        transform: Translate { y: (1 - win.reveal) * -8 }
    }
}
