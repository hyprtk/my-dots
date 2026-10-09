// Settings — centred layer-shell panel with nine pages editing the Qt bar's own
// config (~/.config/hyprtk-bar-qt/config.json), separate from the GTK bar's.
//
// Bar / Themes / Fonts / Animations / Arc Menu / Menu / Quicklinks / Modules /
// Widgets. Changes are debounced and written via backend/.../barsettings.py.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"
import "../state"
import "../data"
import "../components"

PanelWindow {
    id: win

    visible: UiState.settingsOpen
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 820
    implicitHeight: 620

    // Open on the focused monitor (captured when shown).
    property var targetScreen: null
    screen: targetScreen

    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        reveal = visible ? 1 : 0;
        if (visible)
            targetScreen = Screens.focused();
    }

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/barsettings.py").toString().replace("file://", "")

    property int page: 0
    readonly property var pageNames: ["Bar", "Themes", "Fonts", "Animations", "Arc Menu", "Menu", "Quicklinks", "Modules", "Widgets"]
    readonly property var arcPositions: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
    readonly property var moduleIds: ["start_button", "quicklinks", "workspaces", "tasklist", "window", "updates", "net", "tray", "kbstate", "notifications", "clock", "media", "sysmon", "themer", "settings", "quicksettings"]
    readonly property var widgetIds: ["clock", "weather", "visualizer", "disk", "network", "resources", "sysinfo"]

    // ── debounced config writer ────────────────────────────────────────
    property var pending: ({})
    Timer { id: flushTimer; interval: 200; onTriggered: win.flush() }
    Process {
        id: setProc
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("hyprtk-bar-qt settings: write failed (exit " + code + ")");
        }
    }

    // Keep the desktop widgets' opacity in step with the bar opacity.
    readonly property string wbase:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/").toString().replace("file://", "")
    property real pendingWidgetOpacity: 0
    Timer {
        id: wOpTimer
        interval: 200
        onTriggered: {
            wOpProc.command = ["python3", win.wbase + "widgets_layout.py",
                "set-opacity", "--value", String(win.pendingWidgetOpacity)];
            wOpProc.running = true;
        }
    }
    Process { id: wOpProc }
    function syncWidgetOpacity(v) {
        win.pendingWidgetOpacity = v;
        wOpTimer.restart();
    }

    function set(path, value) {
        const parts = String(path).split(".");
        let node = win.pending;
        for (let i = 0; i < parts.length - 1; i++)
            node = (node[parts[i]] = node[parts[i]] || ({}));
        node[parts[parts.length - 1]] = value;
        flushTimer.restart();
    }
    function flush() {
        if (Object.keys(win.pending).length === 0)
            return;
        const patch = win.pending;
        win.pending = ({});
        setProc.command = ["python3", win.backend, "set", "--json", JSON.stringify(patch)];
        setProc.running = true;
    }
    // Read a dotted path from the Qt config.
    function g(path, fallback) {
        let node = BarConfig.cfg;
        for (const p of String(path).split(".")) {
            if (node === null || node === undefined)
                return fallback;
            node = node[p];
        }
        return (node === undefined || node === null) ? fallback : node;
    }
    function idx(list, v) {
        const i = (list || []).indexOf(v);
        return i < 0 ? 0 : i;
    }

    // ── layout (modules) helpers ───────────────────────────────────────
    function sectionOf(id) {
        if ((BarConfig.layoutLeft || []).indexOf(id) >= 0) return "left";
        if ((BarConfig.layoutCenter || []).indexOf(id) >= 0) return "center";
        if ((BarConfig.layoutRight || []).indexOf(id) >= 0) return "right";
        return "";
    }
    function setSection(id, section) {
        const clean = (list) => (list || []).filter(x => x !== id);
        let L = clean(BarConfig.layoutLeft);
        let C = clean(BarConfig.layoutCenter);
        let R = clean(BarConfig.layoutRight);
        if (section === "left") L.push(id);
        else if (section === "center") C.push(id);
        else if (section === "right") R.push(id);
        win.set("layout", { left: L, center: C, right: R });
    }
    // Reorder a module within its current section (up/down).
    function moveModule(id, dir) {
        const s = win.sectionOf(id);
        if (!s)
            return;
        const L = win.cloneArr(BarConfig.layoutLeft);
        const C = win.cloneArr(BarConfig.layoutCenter);
        const R = win.cloneArr(BarConfig.layoutRight);
        const arr = s === "left" ? L : (s === "center" ? C : R);
        const i = arr.indexOf(id);
        const j = i + dir;
        if (i < 0 || j < 0 || j >= arr.length)
            return;
        const t = arr[i]; arr[i] = arr[j]; arr[j] = t;
        win.set("layout", { left: L, center: C, right: R });
    }
    function moduleEnabledBlock(id) {
        const map = {
            start_button: "center", themer: "themer", quicklinks: "quicklinks",
            workspaces: "workspaces", window: "window", updates: "updates",
            tray: "tray", notifications: "notifications", clock: "clock",
            media: "media", sysmon: "sysmon", quicksettings: "quicksettings"
        };
        return map[id] || "";
    }
    // Full config key backing a module's Enabled checkbox. The start button's
    // flag is `center.start_button` (NOT `center.enabled`), so it is special-cased.
    function moduleEnabledKey(id) {
        if (id === "start_button")
            return "center.start_button";
        const b = win.moduleEnabledBlock(id);
        return b ? b + ".enabled" : "";
    }

    // ── module / widget presentation helpers ───────────────────────────
    readonly property var moduleLabels: ({
        start_button: "Start Button", quicklinks: "Quick Links", workspaces: "Workspaces",
        tasklist: "Task List", window: "Active Window", updates: "Updates", net: "Network",
        tray: "System Tray", kbstate: "Keyboard State", notifications: "Notifications",
        clock: "Clock", media: "Media", sysmon: "System Monitor",
        themer: "Theme Manager", settings: "Settings", quicksettings: "Quick Settings"
    })
    function moduleLabel(id) { return win.moduleLabels[id] || id; }
    function moduleHasOptions(id) {
        return ["workspaces", "clock", "media", "updates", "window", "tray", "notifications"].indexOf(id) >= 0;
    }
    readonly property var widgetLabels: ({
        clock: "Clock", weather: "Weather", visualizer: "Visualizer", disk: "Disk",
        network: "Network", resources: "Resources", sysinfo: "System Info"
    })
    function widgetLabel(id) { return win.widgetLabels[id] || id; }

    // Accordion expansion state for the Modules / Widgets pages.
    property var expMod: ({})
    property var expWid: ({})
    function toggleMod(id) {
        const m = Object.assign({}, win.expMod);
        m[id] = !m[id];
        win.expMod = m;
    }
    function toggleWid(id) {
        const m = Object.assign({}, win.expWid);
        m[id] = !m[id];
        win.expWid = m;
    }

    // ── quicklinks helpers ─────────────────────────────────────────────
    function links() { return win.g("quicklinks.links", []); }
    function setLink(i, field, value) {
        const arr = JSON.parse(JSON.stringify(win.links()));
        arr[i][field] = value;
        win.set("quicklinks.links", arr);
    }
    function addLink() {
        const arr = JSON.parse(JSON.stringify(win.links()));
        arr.push({ id: "custom" + arr.length, label: "", icon: "\uf013", command: "", command_right: "", command_middle: "" });
        win.set("quicklinks.links", arr);
    }
    function removeLink(i) {
        const arr = JSON.parse(JSON.stringify(win.links()));
        arr.splice(i, 1);
        win.set("quicklinks.links", arr);
    }

    // ── widgets helpers ────────────────────────────────────────────────
    function widgetVal(id, key, fallback) { return win.g("widgets." + id + "." + key, fallback); }
    function setWidget(id, key, value) { win.set("widgets." + id + "." + key, value); }
    function cloneArr(a) { return JSON.parse(JSON.stringify(a || [])); }
    function widgetStyles(id) {
        if (id === "clock")
            return ["digital", "text", "dials"];
        if (id === "visualizer")
            return ["bars", "wave", "mirror", "dots", "glow"];
        return [];
    }
    function hasColors(id) {
        return ["clock", "weather", "visualizer", "disk", "network", "resources", "sysinfo"].indexOf(id) >= 0;
    }

    // ── theme helpers (theme block + Qt override + rofi variant kept in sync,
    // so the Settings page and the Themer window cannot shadow each other) ────
    function setTheme(key, value) {
        // Merge the edit into the full theme and hand it to the shared writer
        // (writes both config representations and re-links rofi).
        const src = key === "source" ? value : win.g("theme.source", "pywal");
        const nm = key === "theme_name" ? value : win.g("theme.theme_name", "");
        const bg = key === "background" ? value : win.g("theme.background", "");
        const fg = key === "foreground" ? value : win.g("theme.foreground", "");
        const ac = key === "accent" ? value : win.g("theme.accent", "");
        ThemeSync.apply(src, nm, bg, fg, ac);
    }
    readonly property string themesBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/themes.py").toString().replace("file://", "")
    property var installedThemes: []
    function refreshInstalledThemes() { if (!themesProc.running) themesProc.running = true; }
    function applyImportedTheme(name) {
        const t = win.installedThemes.find(x => x.name === name);
        const p = (t && t.palette) ? t.palette : ({});
        ThemeSync.apply("imported", name, p.background || "", p.foreground || "", p.accent || "");
    }
    Process {
        id: themesProc
        command: ["python3", win.themesBackend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.installedThemes = (JSON.parse(text).themes) || [];
                } catch (e) {
                    win.installedThemes = [];
                }
            }
        }
    }
    Component.onCompleted: win.refreshInstalledThemes()

    // ── arc menu item editor ───────────────────────────────────────────
    function arcItems() { return win.g("arcmenu.items", []); }
    function setArcItem(i, field, value) {
        const a = win.cloneArr(win.arcItems());
        a[i][field] = value;
        win.set("arcmenu.items", a);
    }
    function addArcItem() {
        const a = win.cloneArr(win.arcItems());
        a.push({ glyph: "\uf013", command: "", tooltip: "", action: "" });
        win.set("arcmenu.items", a);
    }
    function removeArcItem(i) {
        const a = win.cloneArr(win.arcItems());
        a.splice(i, 1);
        win.set("arcmenu.items", a);
    }
    function moveArcItem(i, dir) {
        const a = win.cloneArr(win.arcItems());
        const j = i + dir;
        if (j < 0 || j >= a.length)
            return;
        const t = a[i]; a[i] = a[j]; a[j] = t;
        win.set("arcmenu.items", a);
    }

    // ── menu power + favourites ────────────────────────────────────────
    readonly property var powerKeys: ["lock", "logout", "reboot", "shutdown", "suspend", "hibernate"]
    function powerVal(k) { return win.g("menu.power." + k, ""); }
    function setPower(k, v) { win.set("menu.power", { [k]: v }); }
    function favorites() { return win.g("menu.favorites", []); }
    function removeFavorite(i) {
        const a = win.cloneArr(win.favorites());
        a.splice(i, 1);
        win.set("menu.favorites", a);
    }
    function addFavorite(id) {
        if (!id) return;
        const a = win.cloneArr(win.favorites());
        if (a.indexOf(id) < 0) a.push(id);
        win.set("menu.favorites", a);
    }

    // ── reusable row ───────────────────────────────────────────────────
    component SRow: RowLayout {
        id: r
        default property alias content: r.data
        Layout.fillWidth: true
        spacing: 8
        property string label: ""
        Text {
            text: r.label
            color: Theme.foreground
            font.pixelSize: 12
            Layout.preferredWidth: 150
            elide: Text.ElideRight
        }
    }

    // Compact labelled control for the wrapping widget-option Flows.
    component WOpt: RowLayout {
        id: wo
        spacing: 4
        property string label: ""
        Text { text: wo.label; color: Theme.dim; font.pixelSize: 10 }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.95, Theme.opacity))
        opacity: win.reveal
        transform: Translate { y: (1 - win.reveal) * -8 }
    }

    IpcHandler {
        target: "settings"
        function toggle() { UiState.settingsOpen = !UiState.settingsOpen; }
        function open() { UiState.settingsOpen = true; }
        function close() { UiState.settingsOpen = false; }
    }


    RowLayout {
        anchors.fill: parent
        spacing: 0
        opacity: win.reveal
        transform: Translate { y: (1 - win.reveal) * -8 }

        // ── sidebar ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 150
            topLeftRadius: 14
            bottomLeftRadius: 14
            color: Theme.alpha(Theme.background, 0.6)
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                Repeater {
                    model: win.pageNames
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: win.page === index
                            ? Theme.alpha(Theme.accent, 0.85)
                            : (sbHover.hovered ? Theme.alpha(Theme.accent2, 0.15) : "transparent")
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            text: modelData
                            color: win.page === index ? "#000000" : Theme.foreground
                            font.pixelSize: 12
                        }
                        HoverHandler { id: sbHover }
                        TapHandler { onTapped: win.page = index }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // ── content ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 12

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                // Bar ──────────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: barCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: barCol
                        width: parent.width
                        spacing: 8
                        SRow {
                            label: "Position"
                            TComboBox {
                                model: ["top", "bottom"]
                                currentIndex: win.idx(model, win.g("position", "top"))
                                onActivated: win.set("position", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Height"
                            TSpinBox { from: 20; to: 120; value: win.g("height", 38); onValueModified: win.set("height", value) }
                        }
                        SRow {
                            label: "Width (% or px)"
                            TTextField { Layout.preferredWidth: 120; text: win.g("width", "75%"); onEditingFinished: win.set("width", text) }
                        }
                        SRow {
                            label: "Align"
                            TComboBox {
                                model: ["left", "center", "right"]
                                currentIndex: win.idx(model, win.g("align", "center"))
                                onActivated: win.set("align", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Gap in (bar\u2194windows)"
                            TSpinBox { from: 0; to: 60; value: win.g("gap_in", 0); onValueModified: win.set("gap_in", value) }
                        }
                        SRow {
                            label: "Gap out (bar\u2194edge)"
                            TSpinBox { from: 0; to: 60; value: win.g("gap_out", 0); onValueModified: win.set("gap_out", value) }
                        }
                        SRow {
                            label: "Corner radius"
                            TSpinBox { from: 0; to: 40; value: win.g("radius", 12); onValueModified: win.set("radius", value) }
                        }
                        SRow {
                            label: "Border width (bar & panels)"
                            TSpinBox { from: 0; to: 8; value: win.g("border_width", 2); onValueModified: win.set("border_width", value) }
                        }
                        SRow {
                            label: "Opacity"
                            TSlider {
                                Layout.preferredWidth: 200
                                from: 0.2; to: 1.0; stepSize: 0.05
                                value: win.g("opacity", 0.75)
                                onMoved: { win.set("opacity", value); win.syncWidgetOpacity(value); }
                            }
                            Text { text: Math.round(win.g("opacity", 0.75) * 100) + "%"; color: Theme.dim; font.pixelSize: 11 }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Themes ────────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: thCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: thCol
                        width: parent.width
                        spacing: 8
                        SRow {
                            label: "Source"
                            TComboBox {
                                model: ["pywal", "imported", "manual", ""]
                                currentIndex: win.idx(["pywal", "imported", "manual", ""], win.g("theme.source", "pywal"))
                                onActivated: win.setTheme("source", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Installed theme"
                            visible: win.g("theme.source", "pywal") === "imported"
                            TComboBox {
                                Layout.preferredWidth: 240
                                model: win.installedThemes.map(t => t.name)
                                currentIndex: win.idx(model, win.g("theme.theme_name", ""))
                                onActivated: win.applyImportedTheme(model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Theme name"
                            TTextField { Layout.fillWidth: true; text: win.g("theme.theme_name", ""); onEditingFinished: win.setTheme("theme_name", text) }
                        }
                        SRow {
                            label: "Background"
                            TTextField { Layout.fillWidth: true; placeholderText: "#1a1b26"; text: win.g("theme.background", ""); onEditingFinished: win.setTheme("background", text) }
                        }
                        SRow {
                            label: "Foreground"
                            TTextField { Layout.fillWidth: true; placeholderText: "#c0caf5"; text: win.g("theme.foreground", ""); onEditingFinished: win.setTheme("foreground", text) }
                        }
                        SRow {
                            label: "Accent"
                            TTextField { Layout.fillWidth: true; placeholderText: "#7aa2f7"; text: win.g("theme.accent", ""); onEditingFinished: win.setTheme("accent", text) }
                        }
                        SRow {
                            label: "Border animation"
                            TCheckBox { checked: win.g("theme.border_animation", true); onToggled: win.set("theme.border_animation", checked) }
                        }
                        SRow {
                            label: "Swatches"
                            Repeater {
                                model: [Theme.background, Theme.foreground, Theme.accent, Theme.accent2, Theme.dim, Theme.err, Theme.warn]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 30; height: 30; radius: 6; color: modelData
                                    border.color: Theme.alpha(Theme.foreground, 0.3); border.width: 1
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Fonts ─────────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: fnCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: fnCol
                        width: parent.width
                        spacing: 8
                        SRow {
                            label: "Family (blank = sys)"
                            TComboBox {
                                Layout.preferredWidth: 240
                                model: [""].concat(Qt.fontFamilies())
                                currentIndex: win.idx(model, win.g("font.family", ""))
                                onActivated: win.set("font.family", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Size (px)"
                            TSpinBox { from: 8; to: 40; value: win.g("font.size", 12); onValueModified: win.set("font.size", value) }
                        }
                        SRow {
                            label: "Icon size (0=auto)"
                            TSpinBox { from: 0; to: 48; value: win.g("font.icon_size", 0); onValueModified: win.set("font.icon_size", value) }
                        }
                        SRow {
                            label: "Quicklink icons"
                            TSpinBox { from: 0; to: 48; value: win.g("quicklinks.icon_size", 0); onValueModified: win.set("quicklinks.icon_size", value) }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Animations ────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: anCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: anCol
                        width: parent.width
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Animate the bar's border colour. Low/High follow Hyprland's animation files; Custom sets an independent speed."
                            color: Theme.dim; font.pixelSize: 11; wrapMode: Text.WordWrap
                        }
                        SRow {
                            label: "Animated border"
                            TCheckBox { checked: win.g("theme.border_animation", true); onToggled: win.set("theme.border_animation", checked) }
                        }
                        SRow {
                            label: "Mode"
                            TComboBox {
                                model: ["low", "high", "custom"]
                                currentIndex: win.idx(model, win.g("animations.mode", "high"))
                                onActivated: win.set("animations.mode", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Custom speed"
                            TSpinBox { from: 1; to: 200; value: win.g("animations.speed", 15); onValueModified: win.set("animations.speed", value) }
                        }
                        SRow {
                            label: "UI animations"
                            TCheckBox { checked: Config.uiAnimations; onToggled: { Config.uiAnimations = checked; Config.save(); } }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Arc Menu ──────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: arcCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: arcCol
                        width: parent.width
                        spacing: 8
                        SRow {
                            label: "Enabled"
                            TCheckBox { checked: win.g("arcmenu.enabled", true); onToggled: win.set("arcmenu.enabled", checked) }
                        }
                        SRow {
                            label: "Position"
                            TComboBox {
                                model: win.arcPositions
                                currentIndex: win.idx(win.arcPositions, win.g("arcmenu.position", "bottom-right"))
                                onActivated: win.set("arcmenu.position", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Shape"
                            TComboBox {
                                model: ["circle", "square"]
                                currentIndex: win.idx(model, win.g("arcmenu.shape", "circle"))
                                onActivated: win.set("arcmenu.shape", model[currentIndex])
                            }
                        }
                        SRow { label: "Radius"; TSpinBox { from: 40; to: 400; value: win.g("arcmenu.radius", 140); onValueModified: win.set("arcmenu.radius", value) } }
                        SRow { label: "FAB size"; TSpinBox { from: 24; to: 96; value: win.g("arcmenu.fab_size", 56); onValueModified: win.set("arcmenu.fab_size", value) } }
                        SRow { label: "Item size"; TSpinBox { from: 24; to: 96; value: win.g("arcmenu.item_size", 48); onValueModified: win.set("arcmenu.item_size", value) } }
                        SRow { label: "Margin"; TSpinBox { from: 0; to: 200; value: win.g("arcmenu.margin", 24); onValueModified: win.set("arcmenu.margin", value) } }
                        SRow { label: "Animation (ms)"; TSpinBox { from: 0; to: 1000; stepSize: 20; value: win.g("arcmenu.animation_time", 300); onValueModified: win.set("arcmenu.animation_time", value) } }
                        SRow {
                            label: "FAB glyph"
                            TTextField { Layout.fillWidth: true; text: win.g("arcmenu.fab_glyph", "\uf00a"); onEditingFinished: win.set("arcmenu.fab_glyph", text) }
                        }
                        SRow {
                            label: "Use pywal colours"
                            TCheckBox { checked: win.g("arcmenu.use_pywal", true); onToggled: win.set("arcmenu.use_pywal", checked) }
                        }
                        SRow {
                            label: "FAB colour"
                            TTextField { Layout.preferredWidth: 120; text: win.g("arcmenu.fab_color", "#C084FC"); onEditingFinished: win.set("arcmenu.fab_color", text) }
                        }
                        SRow {
                            label: "Item colour"
                            TTextField { Layout.preferredWidth: 120; text: win.g("arcmenu.item_color", "#22D3EE"); onEditingFinished: win.set("arcmenu.item_color", text) }
                        }
                        SRow {
                            label: "Close on click"
                            TCheckBox { checked: win.g("arcmenu.close_on_click", true); onToggled: win.set("arcmenu.close_on_click", checked) }
                        }
                        Text { text: "Menu items"; color: Theme.accent; font.bold: true; font.pixelSize: 12; Layout.topMargin: 6 }
                        Repeater {
                            model: win.arcItems()
                            delegate: RowLayout {
                                id: arcItem
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 6
                                TTextField { Layout.preferredWidth: 40; text: arcItem.modelData.glyph || ""; onEditingFinished: win.setArcItem(arcItem.index, "glyph", text) }
                                TTextField { Layout.fillWidth: true; placeholderText: "command"; text: arcItem.modelData.command || ""; onEditingFinished: win.setArcItem(arcItem.index, "command", text) }
                                TTextField { Layout.preferredWidth: 130; placeholderText: "tooltip"; text: arcItem.modelData.tooltip || ""; onEditingFinished: win.setArcItem(arcItem.index, "tooltip", text) }
                                TComboBox {
                                    Layout.preferredWidth: 110
                                    model: ["", "settings", "themer", "clipboard"]
                                    currentIndex: win.idx(model, arcItem.modelData.action || "")
                                    onActivated: win.setArcItem(arcItem.index, "action", model[currentIndex])
                                }
                                TButton { text: "\u2191"; implicitWidth: 30; onClicked: win.moveArcItem(arcItem.index, -1) }
                                TButton { text: "\u2193"; implicitWidth: 30; onClicked: win.moveArcItem(arcItem.index, 1) }
                                TButton { text: "\u2715"; implicitWidth: 30; onClicked: win.removeArcItem(arcItem.index) }
                            }
                        }
                        TButton { text: "Add item"; onClicked: win.addArcItem() }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Menu ──────────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: mnCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: mnCol
                        width: parent.width
                        spacing: 8
                        SRow {
                            label: "Enabled"
                            TCheckBox { checked: win.g("menu.enabled", true); onToggled: win.set("menu.enabled", checked) }
                        }
                        SRow {
                            label: "Follow pywal"
                            TCheckBox { checked: win.g("menu.follow_bar", true); onToggled: win.set("menu.follow_bar", checked) }
                        }
                        SRow {
                            label: "Layout"
                            TComboBox {
                                model: ["whisker", "win7", "win11", "plasma"]
                                currentIndex: win.idx(model, win.g("menu.layout", "whisker"))
                                onActivated: win.set("menu.layout", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Position"
                            TComboBox {
                                model: ["auto", "top", "bottom"]
                                currentIndex: win.idx(model, win.g("menu.position", "auto"))
                                onActivated: win.set("menu.position", model[currentIndex])
                            }
                        }
                        SRow {
                            label: "Align"
                            TComboBox {
                                model: ["left", "center", "right"]
                                currentIndex: win.idx(model, win.g("menu.align", "left"))
                                onActivated: win.set("menu.align", model[currentIndex])
                            }
                        }
                        SRow { label: "Gap in"; TSpinBox { from: 0; to: 60; value: win.g("menu.gap_in", 4); onValueModified: win.set("menu.gap_in", value) } }
                        SRow { label: "Gap out"; TSpinBox { from: 0; to: 60; value: win.g("menu.gap_out", 5); onValueModified: win.set("menu.gap_out", value) } }
                        SRow { label: "Width"; TSpinBox { from: 400; to: 1600; stepSize: 20; value: win.g("menu.width", 920); onValueModified: win.set("menu.width", value) } }
                        SRow { label: "Height"; TSpinBox { from: 320; to: 1000; stepSize: 20; value: win.g("menu.height", 580); onValueModified: win.set("menu.height", value) } }
                        SRow { label: "Sidebar width"; TSpinBox { from: 120; to: 300; value: win.g("menu.sidebar_width", 180); onValueModified: win.set("menu.sidebar_width", value) } }
                        SRow { label: "Recents width"; TSpinBox { from: 120; to: 360; value: win.g("menu.recents_width", 230); onValueModified: win.set("menu.recents_width", value) } }
                        SRow {
                            label: "Show recents"
                            TCheckBox { checked: win.g("menu.show_recents", true); onToggled: win.set("menu.show_recents", checked) }
                        }
                        SRow { label: "Max recents"; TSpinBox { from: 0; to: 30; value: win.g("menu.max_recents", 10); onValueModified: win.set("menu.max_recents", value) } }
                        Text { text: "Power commands"; color: Theme.accent; font.bold: true; font.pixelSize: 12; Layout.topMargin: 6 }
                        Repeater {
                            model: win.powerKeys
                            delegate: SRow {
                                required property string modelData
                                label: modelData
                                TTextField { Layout.fillWidth: true; text: win.powerVal(modelData); onEditingFinished: win.setPower(modelData, text) }
                            }
                        }
                        Text { text: "Favourites"; color: Theme.accent; font.bold: true; font.pixelSize: 12; Layout.topMargin: 6 }
                        Repeater {
                            model: win.favorites()
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Text { text: modelData; color: Theme.foreground; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                                TButton { text: "\u2715"; implicitWidth: 30; onClicked: win.removeFavorite(index) }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            TTextField {
                                id: favAdd
                                Layout.fillWidth: true
                                placeholderText: "app id (e.g. firefox.desktop)"
                                onAccepted: { win.addFavorite(text); text = ""; }
                            }
                            TButton { text: "Add favourite"; onClicked: { win.addFavorite(favAdd.text); favAdd.text = ""; } }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Quicklinks ─────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8
                    SRow {
                        label: "Enabled"
                        TCheckBox { checked: win.g("quicklinks.enabled", true); onToggled: win.set("quicklinks.enabled", checked) }
                    }
                    Flickable {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentHeight: qlCol.implicitHeight; clip: true
                        ColumnLayout {
                            id: qlCol
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: win.links()
                                delegate: RowLayout {
                                    id: ql
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TTextField { Layout.preferredWidth: 40; text: ql.modelData.icon || ""; onEditingFinished: win.setLink(ql.index, "icon", text) }
                                    TTextField { Layout.fillWidth: true; placeholderText: "command"; text: ql.modelData.command || ""; onEditingFinished: win.setLink(ql.index, "command", text) }
                                    TTextField { Layout.preferredWidth: 160; placeholderText: "right command"; text: ql.modelData.command_right || ""; onEditingFinished: win.setLink(ql.index, "command_right", text) }
                                    TButton { text: "\u2715"; onClicked: win.removeLink(ql.index) }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                TButton { text: "Add link"; onClicked: win.addLink() }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // Modules ────────────────────────────────────────────────
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: modCol.implicitHeight; clip: true
                    ColumnLayout {
                        id: modCol
                        width: parent.width
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Enable a module and pick the bar section it lives in. Tap the arrow to reveal its options."
                            color: Theme.dim; font.pixelSize: 11; wrapMode: Text.WordWrap
                        }
                        Repeater {
                            model: win.moduleIds
                            delegate: Rectangle {
                                id: mcard
                                required property string modelData
                                Layout.fillWidth: true
                                readonly property bool hasOpts: win.moduleHasOptions(mcard.modelData)
                                readonly property bool expanded: win.expMod[mcard.modelData] === true
                                implicitHeight: mcol.implicitHeight + 16
                                radius: 8
                                color: Theme.alpha(Theme.background, 0.42)
                                border.width: 1
                                border.color: mcard.expanded ? Theme.alpha(Theme.accent, 0.55)
                                                             : Theme.alpha(Theme.accent2, 0.15)

                                ColumnLayout {
                                    id: mcol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: win.moduleLabel(mcard.modelData)
                                            color: Theme.foreground; font.bold: true; font.pixelSize: 12
                                            elide: Text.ElideRight
                                            Layout.preferredWidth: 122
                                        }
                                        TCheckBox {
                                            text: "Enabled"
                                            visible: win.moduleEnabledKey(mcard.modelData) !== ""
                                            checked: win.g(win.moduleEnabledKey(mcard.modelData), true)
                                            onToggled: win.set(win.moduleEnabledKey(mcard.modelData), checked)
                                        }
                                        TComboBox {
                                            Layout.preferredWidth: 106
                                            model: ["Off", "Left", "Center", "Right"]
                                            currentIndex: {
                                                const s = win.sectionOf(mcard.modelData);
                                                return s === "left" ? 1 : s === "center" ? 2 : s === "right" ? 3 : 0;
                                            }
                                            onActivated: win.setSection(mcard.modelData, ["", "left", "center", "right"][currentIndex])
                                        }
                                        TButton { text: "\u2191"; implicitWidth: 28; enabled: win.sectionOf(mcard.modelData) !== ""; onClicked: win.moveModule(mcard.modelData, -1) }
                                        TButton { text: "\u2193"; implicitWidth: 28; enabled: win.sectionOf(mcard.modelData) !== ""; onClicked: win.moveModule(mcard.modelData, 1) }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            visible: mcard.hasOpts
                                            implicitWidth: 28; implicitHeight: 24; radius: 6
                                            color: chevHover.hovered ? Theme.alpha(Theme.accent2, 0.2) : "transparent"
                                            Text { anchors.centerIn: parent; text: mcard.expanded ? "\uf077" : "\uf078"; color: Theme.accent; font.pixelSize: 11 }
                                            HoverHandler { id: chevHover }
                                            TapHandler { onTapped: win.toggleMod(mcard.modelData) }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "workspaces"
                                        SRow { label: "Show empty"; TCheckBox { checked: win.g("workspaces.show_empty", true); onToggled: win.set("workspaces.show_empty", checked) } }
                                        SRow { label: "Max shown"; TSpinBox { from: 0; to: 32; value: win.g("workspaces.max", 0); onValueModified: win.set("workspaces.max", value) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "clock"
                                        SRow { label: "Time format"; TTextField { Layout.fillWidth: true; text: win.g("clock.format", "ddd HH:mm:ss"); onEditingFinished: win.set("clock.format", text) } }
                                        SRow { label: "Date format"; TTextField { Layout.fillWidth: true; text: win.g("clock.date_format", "dddd, dd MMMM"); onEditingFinished: win.set("clock.date_format", text) } }
                                        SRow { label: "Calendar popup"; TCheckBox { checked: win.g("clock.calendar", true); onToggled: win.set("clock.calendar", checked) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "media"
                                        SRow { label: "Transport controls"; TCheckBox { checked: win.g("media.show_controls", true); onToggled: win.set("media.show_controls", checked) } }
                                        SRow { label: "Show track text"; TCheckBox { checked: win.g("media.show_text", true); onToggled: win.set("media.show_text", checked) } }
                                        SRow { label: "Max text length"; TSpinBox { from: 0; to: 200; value: win.g("media.max_length", 48); onValueModified: win.set("media.max_length", value) } }
                                        SRow { label: "Text width (px)"; TSpinBox { from: 0; to: 600; stepSize: 10; value: win.g("media.text_width", 180); onValueModified: win.set("media.text_width", value) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "updates"
                                        SRow { label: "Interval (s)"; TSpinBox { from: 30; to: 3600; stepSize: 30; value: win.g("updates.interval", 60); onValueModified: win.set("updates.interval", value) } }
                                        SRow { label: "Script"; TTextField { Layout.fillWidth: true; text: win.g("updates.script", ""); onEditingFinished: win.set("updates.script", text) } }
                                        SRow { label: "Install command"; TTextField { Layout.fillWidth: true; text: win.g("updates.install_command", ""); onEditingFinished: win.set("updates.install_command", text) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "window"
                                        SRow { label: "Max length"; TSpinBox { from: 0; to: 400; value: win.g("window.max_length", 120); onValueModified: win.set("window.max_length", value) } }
                                        SRow { label: "Fixed width"; TSpinBox { from: 0; to: 600; value: win.g("window.width", 0); onValueModified: win.set("window.width", value) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "tray"
                                        SRow { label: "Icon size (0=auto)"; TSpinBox { from: 0; to: 48; value: win.g("tray.icon_size", 0); onValueModified: win.set("tray.icon_size", value) } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: mcard.expanded && mcard.modelData === "notifications"
                                        SRow { label: "Max stored"; TSpinBox { from: 1; to: 500; value: win.g("notifications.max_stored", 50); onValueModified: win.set("notifications.max_stored", value) } }
                                        SRow { label: "Default timeout (ms)"; TSpinBox { from: 1000; to: 60000; stepSize: 500; value: win.g("notifications.default_timeout", 5000); onValueModified: win.set("notifications.default_timeout", value) } }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Widgets ────────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: masters.implicitHeight + 16
                        radius: 8
                        color: Theme.alpha(Theme.background, 0.42)
                        border.width: 1; border.color: Theme.alpha(Theme.accent2, 0.15)
                        RowLayout {
                            id: masters
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 18
                            TCheckBox { text: "Widgets enabled"; checked: win.g("widgets.enabled", false); onToggled: win.set("widgets.enabled", checked) }
                            TCheckBox { text: "Transparent pills"; checked: win.g("widgets.transparent", false); onToggled: win.set("widgets.transparent", checked) }
                            TCheckBox { text: "Borders"; checked: win.g("widgets.border", true); onToggled: win.set("widgets.border", checked) }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentHeight: wCol.implicitHeight; clip: true
                        ColumnLayout {
                            id: wCol
                            width: parent.width
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: "Turn a desktop widget on and choose its screen position. Tap the arrow for size, colours and options."
                                color: Theme.dim; font.pixelSize: 11; wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: win.widgetIds
                                delegate: Rectangle {
                                    id: wcard
                                    required property string modelData
                                    Layout.fillWidth: true
                                    readonly property bool expanded: win.expWid[wcard.modelData] === true
                                    readonly property bool hasColors: win.hasColors(wcard.modelData)
                                    implicitHeight: wcol.implicitHeight + 16
                                    radius: 8
                                    color: Theme.alpha(Theme.background, 0.42)
                                    border.width: 1
                                    border.color: wcard.expanded ? Theme.alpha(Theme.accent, 0.55)
                                                                 : Theme.alpha(Theme.accent2, 0.15)

                                    ColumnLayout {
                                        id: wcol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: 8
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text { text: win.widgetLabel(wcard.modelData); color: Theme.foreground; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 92 }
                                            TCheckBox { text: "On"; checked: win.g("widgets." + wcard.modelData + ".enabled", false); onToggled: win.setWidget(wcard.modelData, "enabled", checked) }
                                            TComboBox {
                                                Layout.preferredWidth: 128
                                                model: ["top-left", "top-center", "top-right", "center-left", "center", "center-right", "bottom-left", "bottom-center", "bottom-right", "free"]
                                                currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "position", "top-left"))
                                                onActivated: win.setWidget(wcard.modelData, "position", model[currentIndex])
                                            }
                                            Text { text: "Opacity"; color: Theme.dim; font.pixelSize: 10 }
                                            TSlider {
                                                Layout.preferredWidth: 90
                                                from: 0.1; to: 1.0; stepSize: 0.05
                                                value: win.widgetVal(wcard.modelData, "opacity", 0.75)
                                                onMoved: win.setWidget(wcard.modelData, "opacity", value)
                                            }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                implicitWidth: 28; implicitHeight: 24; radius: 6
                                                color: wchev.hovered ? Theme.alpha(Theme.accent2, 0.2) : "transparent"
                                                Text { anchors.centerIn: parent; text: wcard.expanded ? "\uf077" : "\uf078"; color: Theme.accent; font.pixelSize: 11 }
                                                HoverHandler { id: wchev }
                                                TapHandler { onTapped: win.toggleWid(wcard.modelData) }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            visible: wcard.expanded

                                            Text { text: "Placement"; color: Theme.dim; font.pixelSize: 10 }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                WOpt { label: "layer"; TComboBox { Layout.preferredWidth: 105; model: ["background", "bottom", "top"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "layer", "bottom")); onActivated: win.setWidget(wcard.modelData, "layer", model[currentIndex]) } }
                                                WOpt { label: "X"; TSpinBox { from: 0; to: 8000; value: win.widgetVal(wcard.modelData, "margin_x", 40); onValueModified: win.setWidget(wcard.modelData, "margin_x", value) } }
                                                WOpt { label: "Y"; TSpinBox { from: 0; to: 8000; value: win.widgetVal(wcard.modelData, "margin_y", 40); onValueModified: win.setWidget(wcard.modelData, "margin_y", value) } }
                                                WOpt { label: "W"; TSpinBox { from: 0; to: 4000; value: win.widgetVal(wcard.modelData, "width", 280); onValueModified: win.setWidget(wcard.modelData, "width", value) } }
                                                WOpt { label: "H"; TSpinBox { from: 0; to: 4000; value: win.widgetVal(wcard.modelData, "height", 0); onValueModified: win.setWidget(wcard.modelData, "height", value) } }
                                                WOpt { label: "radius"; TSpinBox { from: 0; to: 60; value: win.widgetVal(wcard.modelData, "radius", 16); onValueModified: win.setWidget(wcard.modelData, "radius", value) } }
                                                WOpt { label: "pad"; TSpinBox { from: 0; to: 80; value: win.widgetVal(wcard.modelData, "padding", 18); onValueModified: win.setWidget(wcard.modelData, "padding", value) } }
                                                WOpt { label: "scale%"; TSpinBox { from: 50; to: 200; stepSize: 5; value: Math.round(win.widgetVal(wcard.modelData, "scale", 1) * 100); onValueModified: win.setWidget(wcard.modelData, "scale", value / 100) } }
                                                WOpt { label: "snap group"; TTextField { Layout.preferredWidth: 90; placeholderText: "group"; text: win.widgetVal(wcard.modelData, "snap_group", ""); onEditingFinished: win.setWidget(wcard.modelData, "snap_group", text) } }
                                                WOpt { label: "axis"; TComboBox { Layout.preferredWidth: 100; model: ["horizontal", "vertical"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "snap_axis", "horizontal")); onActivated: win.setWidget(wcard.modelData, "snap_axis", model[currentIndex]) } }
                                                WOpt { label: "order"; TSpinBox { from: 0; to: 99; value: win.widgetVal(wcard.modelData, "snap_order", 0); onValueModified: win.setWidget(wcard.modelData, "snap_order", value) } }
                                            }

                                            Text { text: "Colours"; color: Theme.dim; font.pixelSize: 10; visible: wcard.hasColors }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.hasColors
                                                WOpt { label: "bg"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "background", ""); onEditingFinished: win.setWidget(wcard.modelData, "background", text) } }
                                                WOpt { label: "fg"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "foreground", ""); onEditingFinished: win.setWidget(wcard.modelData, "foreground", text) } }
                                                WOpt { label: "accent"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "accent", ""); onEditingFinished: win.setWidget(wcard.modelData, "accent", text) } }
                                            }

                                            Text { text: "Options"; color: Theme.dim; font.pixelSize: 10 }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "clock"
                                                WOpt { label: "style"; TComboBox { Layout.preferredWidth: 100; model: win.widgetStyles("clock"); currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "style", "digital")); onActivated: win.setWidget(wcard.modelData, "style", model[currentIndex]) } }
                                                WOpt { label: "time fmt"; TTextField { Layout.preferredWidth: 130; text: win.widgetVal(wcard.modelData, "time_format", "HH:mm"); onEditingFinished: win.setWidget(wcard.modelData, "time_format", text) } }
                                                WOpt { label: "date fmt"; TTextField { Layout.preferredWidth: 150; text: win.widgetVal(wcard.modelData, "date_format", "dddd, dd MMMM"); onEditingFinished: win.setWidget(wcard.modelData, "date_format", text) } }
                                                WOpt { label: "font"; TTextField { Layout.preferredWidth: 130; text: win.widgetVal(wcard.modelData, "font", ""); onEditingFinished: win.setWidget(wcard.modelData, "font", text) } }
                                                WOpt { label: "theme"; TTextField { Layout.preferredWidth: 110; placeholderText: "theme name"; text: win.widgetVal(wcard.modelData, "theme", ""); onEditingFinished: win.setWidget(wcard.modelData, "theme", text) } }
                                                WOpt { label: "show date"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_date", true); onToggled: win.setWidget(wcard.modelData, "show_date", checked) } }
                                                WOpt { label: "seconds"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_seconds", false); onToggled: win.setWidget(wcard.modelData, "show_seconds", checked) } }
                                                WOpt { label: "dials (1/3)"; TSpinBox { from: 1; to: 3; value: win.widgetVal(wcard.modelData, "dial_count", 1); onValueModified: win.setWidget(wcard.modelData, "dial_count", value) } }
                                                WOpt { label: "ring width"; TSpinBox { from: 2; to: 24; value: win.widgetVal(wcard.modelData, "ring_thickness", 6); onValueModified: win.setWidget(wcard.modelData, "ring_thickness", value) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "weather"
                                                WOpt { label: "city"; TTextField { Layout.preferredWidth: 150; text: win.widgetVal(wcard.modelData, "city", ""); onEditingFinished: win.setWidget(wcard.modelData, "city", text) } }
                                                WOpt { label: "units"; TComboBox { Layout.preferredWidth: 100; model: ["metric", "imperial"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "units", "metric")); onActivated: win.setWidget(wcard.modelData, "units", model[currentIndex]) } }
                                                WOpt { label: "refresh (m)"; TSpinBox { from: 5; to: 240; stepSize: 5; value: win.widgetVal(wcard.modelData, "refresh_minutes", 30); onValueModified: win.setWidget(wcard.modelData, "refresh_minutes", value) } }
                                                WOpt { label: "forecast days"; TSpinBox { from: 0; to: 7; value: win.widgetVal(wcard.modelData, "forecast_days", 4); onValueModified: win.setWidget(wcard.modelData, "forecast_days", value) } }
                                                WOpt { label: "icon"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_icon", true); onToggled: win.setWidget(wcard.modelData, "show_icon", checked) } }
                                                WOpt { label: "temp"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_temp", true); onToggled: win.setWidget(wcard.modelData, "show_temp", checked) } }
                                                WOpt { label: "condition"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_condition", true); onToggled: win.setWidget(wcard.modelData, "show_condition", checked) } }
                                                WOpt { label: "feels"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_feels_like", true); onToggled: win.setWidget(wcard.modelData, "show_feels_like", checked) } }
                                                WOpt { label: "humidity"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_humidity", true); onToggled: win.setWidget(wcard.modelData, "show_humidity", checked) } }
                                                WOpt { label: "wind"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_wind", true); onToggled: win.setWidget(wcard.modelData, "show_wind", checked) } }
                                                WOpt { label: "forecast"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_forecast", true); onToggled: win.setWidget(wcard.modelData, "show_forecast", checked) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "visualizer"
                                                WOpt { label: "style"; TComboBox { Layout.preferredWidth: 100; model: win.widgetStyles("visualizer"); currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "style", "bars")); onActivated: win.setWidget(wcard.modelData, "style", model[currentIndex]) } }
                                                WOpt { label: "bars"; TSpinBox { from: 8; to: 128; value: win.widgetVal(wcard.modelData, "bars", 48); onValueModified: win.setWidget(wcard.modelData, "bars", value) } }
                                                WOpt { label: "fps"; TSpinBox { from: 10; to: 120; value: win.widgetVal(wcard.modelData, "fps", 60); onValueModified: win.setWidget(wcard.modelData, "fps", value) } }
                                                WOpt { label: "colours"; TComboBox { Layout.preferredWidth: 110; model: ["accent", "gradient", "pywal", "custom"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "color_mode", "accent")); onActivated: win.setWidget(wcard.modelData, "color_mode", model[currentIndex]) } }
                                                WOpt { label: "colour"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "color", ""); onEditingFinished: win.setWidget(wcard.modelData, "color", text) } }
                                                WOpt { label: "grad from"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "gradient_from", ""); onEditingFinished: win.setWidget(wcard.modelData, "gradient_from", text) } }
                                                WOpt { label: "grad to"; TTextField { Layout.preferredWidth: 92; placeholderText: "#rrggbb"; text: win.widgetVal(wcard.modelData, "gradient_to", ""); onEditingFinished: win.setWidget(wcard.modelData, "gradient_to", text) } }
                                                WOpt { label: "source"; TComboBox { Layout.preferredWidth: 100; model: ["auto", "cava", "synthetic"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "source", "auto")); onActivated: win.setWidget(wcard.modelData, "source", model[currentIndex]) } }
                                                WOpt { label: "sensitivity%"; TSpinBox { from: 50; to: 300; stepSize: 10; value: Math.round((win.widgetVal(wcard.modelData, "sensitivity", 1) || 1) * 100); onValueModified: win.setWidget(wcard.modelData, "sensitivity", value / 100) } }
                                                WOpt { label: "smoothing%"; TSpinBox { from: 0; to: 90; stepSize: 5; value: Math.round((win.widgetVal(wcard.modelData, "smoothing", 0) || 0) * 100); onValueModified: win.setWidget(wcard.modelData, "smoothing", value / 100) } }
                                                WOpt { label: "orientation"; TComboBox { Layout.preferredWidth: 90; model: ["up", "down"]; currentIndex: win.idx(model, win.widgetVal(wcard.modelData, "orientation", "up")); onActivated: win.setWidget(wcard.modelData, "orientation", model[currentIndex]) } }
                                                WOpt { label: "peak dots"; TCheckBox { checked: win.widgetVal(wcard.modelData, "peak_dots", false); onToggled: win.setWidget(wcard.modelData, "peak_dots", checked) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "disk"
                                                WOpt { label: "bar"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_bar", true); onToggled: win.setWidget(wcard.modelData, "show_bar", checked) } }
                                                WOpt { label: "rates"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_rates", true); onToggled: win.setWidget(wcard.modelData, "show_rates", checked) } }
                                                WOpt { label: "max drives"; TSpinBox { from: 1; to: 16; value: win.widgetVal(wcard.modelData, "drives_max", 4); onValueModified: win.setWidget(wcard.modelData, "drives_max", value) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "network"
                                                WOpt { label: "IP"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_ip", true); onToggled: win.setWidget(wcard.modelData, "show_ip", checked) } }
                                                WOpt { label: "rates"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_rates", true); onToggled: win.setWidget(wcard.modelData, "show_rates", checked) } }
                                                WOpt { label: "graph"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_graph", true); onToggled: win.setWidget(wcard.modelData, "show_graph", checked) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "resources"
                                                WOpt { label: "CPU"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_cpu", true); onToggled: win.setWidget(wcard.modelData, "show_cpu", checked) } }
                                                WOpt { label: "RAM"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_ram", true); onToggled: win.setWidget(wcard.modelData, "show_ram", checked) } }
                                                WOpt { label: "swap"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_swap", true); onToggled: win.setWidget(wcard.modelData, "show_swap", checked) } }
                                                WOpt { label: "temp"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_temp", true); onToggled: win.setWidget(wcard.modelData, "show_temp", checked) } }
                                                WOpt { label: "load"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_load", true); onToggled: win.setWidget(wcard.modelData, "show_load", checked) } }
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: wcard.modelData === "sysinfo"
                                                WOpt { label: "refresh (s)"; TSpinBox { from: 1; to: 120; value: win.widgetVal(wcard.modelData, "refresh_seconds", 10); onValueModified: win.setWidget(wcard.modelData, "refresh_seconds", value) } }
                                                WOpt { label: "disks"; TCheckBox { checked: win.widgetVal(wcard.modelData, "show_disks", true); onToggled: win.setWidget(wcard.modelData, "show_disks", checked) } }
                                            }
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
                Text { text: "Saves to ~/.config/hyprtk-bar-qt/config.json (Qt bar only)"; color: Theme.dim; font.pixelSize: 10; Layout.fillWidth: true }
                TButton { text: "Close"; onClicked: UiState.settingsOpen = false }
            }
        }
    }

    // Animated accent border drawn ON TOP of the sidebar + content, so it reads
    // the same on every edge (the background's border used to be covered by the
    // sidebar on the left/top-left/bottom-left).
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
