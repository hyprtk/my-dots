// Start menu: layout variants (whisker / win7 / win11 / plasma) recreated to
// match the hyprtk GTK menu (assets/screenshots/menu-*.png).
//
// Layout/favourites/recents come from the Qt bar's own `menu` block
// (data/MenuConfig.qml); launches + favourite/recents writes are persisted via
// backend/.../menu.py.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../theme"
import "../config"
import "../state"
import "../components"
import "../data"

PanelWindow {
    id: sm

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    visible: UiState.startMenuOpen && MenuConfig.enabled

    // Open on the start button's monitor (registered on click), else focused.
    property var targetScreen: null
    screen: Screens.byName(BarAnchors.menuScreen) || targetScreen

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/menu.py").toString().replace("file://", "")
    readonly property string filesBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/files.py").toString().replace("file://", "")
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string username: Quickshell.env("USER") || "user"

    property string query: ""
    property string side: "all"        // all | favorites | recents | <category>
    property string browsePath: "~"
    property string browseParent: ""
    property var browseEntries: []
    property var browseHistory: []
    property int plasmaTab: 0          // 0 Applications | 1 Computer | 2 Recently Used
    property bool win11AllApps: false

    readonly property string layout: MenuConfig.layout
    readonly property bool isWhisker: layout === "whisker"
    readonly property bool isWin7: layout === "win7"
    readonly property bool isWin11: layout === "win11"
    readonly property bool isPlasma: layout === "plasma"
    readonly property bool win11AppsView: sm.win11AllApps || sm.query.trim() !== ""

    // ── palette / per-layout accents (GTK: whisker=color5, win7/plasma=color4,
    // win11=color6) ──────────────────────────────────────────────────────
    readonly property color blueColor: Theme.walColor(4, "#89b4fa")
    readonly property color cyanColor: Theme.accent2
    readonly property color layoutAccent: sm.isWin7 || sm.isPlasma ? sm.blueColor
        : (sm.isWin11 ? sm.cyanColor : Theme.accent)
    readonly property color rowHover: Theme.alpha(sm.layoutAccent, sm.isWin7 ? 0.12 : 0.10)
    readonly property color selBg: sm.isWin7 ? sm.blueColor : Theme.alpha(sm.layoutAccent, 0.28)
    readonly property color selBorder: Theme.alpha(sm.layoutAccent, sm.isWin7 ? 0.0 : 0.5)
    readonly property color selectedText: "#ffffff"
    readonly property color footerBg: sm.isWin7 ? Theme.alpha(sm.blueColor, 0.10)
        : sm.isWin11 ? Theme.alpha(Theme.foreground, 0.04)
        : sm.isPlasma ? Theme.alpha(sm.blueColor, 0.06)
        : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.92)
    readonly property color footerBorder: sm.isWin7 ? Theme.alpha(sm.blueColor, 0.35)
        : sm.isWin11 ? Theme.alpha(Theme.foreground, 0.08)
        : sm.isPlasma ? Theme.alpha(sm.blueColor, 0.20)
        : Theme.alpha(Theme.dim, 0.35)

    // ── placement within the bar's extent (like the GTK menu) ───────────
    readonly property real screenW: sm.screen ? sm.screen.width : 0
    readonly property real screenH: sm.screen ? sm.screen.height : 0
    readonly property var insets: BarGeom.insets(sm.screenW)
    readonly property int barW: BarGeom.width(sm.screenW)
    readonly property int menuW: Math.min(MenuConfig.width, sm.barW - 8)
    readonly property int menuH: Math.min(MenuConfig.height, sm.screenH - BarConfig.barHeight - 120)
    readonly property bool atBottom: MenuConfig.followBar
        ? ((MenuConfig.position === "bottom")
            || (MenuConfig.position === "auto" && BarConfig.barPosition === "bottom"))
        : (MenuConfig.position === "bottom")
    readonly property real menuX: MenuConfig.followBar
        ? (MenuConfig.align === "right"
            ? sm.screenW - sm.insets.right - sm.menuW - 4
            : (MenuConfig.align === "center"
                ? Math.round(sm.insets.left + (sm.barW - sm.menuW) / 2)
                : sm.insets.left + 4))
        : (MenuConfig.align === "right"
            ? sm.screenW - sm.menuW - MenuConfig.gapOut
            : (MenuConfig.align === "center"
                ? Math.round((sm.screenW - sm.menuW) / 2)
                : MenuConfig.gapOut))
    readonly property real menuY: {
        const off = MenuConfig.followBar
            ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + MenuConfig.gapIn
            : MenuConfig.gapOut + MenuConfig.gapIn;
        return sm.atBottom ? sm.screenH - off - sm.menuH : off;
    }

    // ── search field metrics per layout ────────────────────────────────
    readonly property int searchH: sm.isWin11 ? 44 : (sm.isPlasma ? 38 : 40)
    readonly property int searchRadius: sm.isWin11 ? 22 : (sm.isPlasma ? 6 : 10)
    readonly property int searchML: sm.isWin11 ? 24 : (sm.isPlasma ? 10 : 12)
    readonly property int searchMT: sm.isWin11 ? 16 : (sm.isPlasma ? 8 : 12)
    readonly property int searchMB: sm.isWin11 ? 8 : 4

    // ── data ───────────────────────────────────────────────────────────
    readonly property var allApps: DesktopEntries.applications.values
    function baseApps() {
        const list = (sm.allApps || []).filter(e => !e.noDisplay);
        // Quickshell returns them unordered; sort alphabetically like the GTK menu.
        return list.slice().sort((a, b) => (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase()));
    }
    // Quickshell's DesktopEntry.id drops the `.desktop` suffix, while the GTK
    // bar (and migrated configs) store ids with it — normalise both ways.
    function _normId(id) {
        return String(id || "").replace(/\.desktop$/, "");
    }
    function byId(id) {
        const want = sm._normId(id);
        if (!want)
            return undefined;
        return (sm.allApps || []).find(e => e.id === want);
    }
    function favoritesEntries() {
        return (MenuConfig.favorites || []).map(sm.byId).filter(e => e);
    }
    function recentsEntries() {
        return (MenuConfig.recents || []).map(sm.byId).filter(e => e);
    }
    // GTK falls back to a default pin/recommended set when favourites/recents
    // are empty (so the win11 tiles + whisker recents pane are never blank).
    readonly property var defaultPinned: [
        "Alacritty", "brave-browser", "thunar", "chromium", "kitty",
        "org.pulseaudio.pavucontrol", "btop"
    ]
    readonly property var defaultRecommended: [
        "Alacritty", "brave-browser", "thunar", "org.pulseaudio.pavucontrol"
    ]
    // Win11 uses the pinned favourites, falling back to the default set; the
    // whisker/win7 favourite strips show only the real favourites (like GTK).
    function pinnedEntries() {
        const favs = sm.favoritesEntries();
        if (favs.length)
            return favs;
        return sm.defaultPinned.map(sm.byId).filter(e => e);
    }
    function recommendedEntries() {
        const r = sm.recentsEntries();
        if (r.length)
            return r;
        return sm.defaultRecommended.map(sm.byId).filter(e => e);
    }
    function shown() {
        const q = sm.query.trim().toLowerCase();
        let list;
        if (q !== "")
            list = sm.baseApps().filter(e => ((e.name || "") + " " + (e.genericName || "") + " " + (e.comment || "") + " " + (e.keywords || "")).toLowerCase().includes(q));
        else if (sm.side === "favorites")
            list = sm.favoritesEntries();
        else if (sm.side === "recents")
            list = sm.recentsEntries();
        else if (sm.side !== "all")
            list = sm.baseApps().filter(e => sm.entryCategories(e).indexOf(sm.side) >= 0);
        else
            list = sm.baseApps();
        return list;
    }
    function isFavorite(id) {
        const want = sm._normId(id);
        return (MenuConfig.favorites || []).some(f => sm._normId(f) === want);
    }

    readonly property var categoryMap: ({
        "Utility": "Accessories", "Accessibility": "Accessories", "Archiving": "Accessories",
        "Development": "Development", "IDE": "Development", "Building": "Development", "Debugger": "Development",
        "Education": "Education", "Science": "Science",
        "Game": "Games", "ActionGame": "Games", "AdventureGame": "Games", "ArcadeGame": "Games",
        "BoardGame": "Games", "CardGame": "Games", "LogicGame": "Games", "SportGame": "Games", "StrategyGame": "Games",
        "Graphics": "Graphics", "2DGraphics": "Graphics", "3DGraphics": "Graphics", "RasterGraphics": "Graphics", "VectorGraphics": "Graphics",
        "Network": "Internet", "WebBrowser": "Internet", "Email": "Internet", "Chat": "Internet", "InstantMessaging": "Internet",
        "AudioVideo": "Multimedia", "Audio": "Multimedia", "Video": "Multimedia", "Music": "Multimedia", "Player": "Multimedia",
        "Office": "Office", "PIM": "Office", "Presentation": "Office", "Spreadsheet": "Office", "WordProcessor": "Office",
        "System": "System", "Monitor": "System", "TerminalEmulator": "System", "FileManager": "System", "Settings": "Settings"
    })
    readonly property var categoryOrder: ["Accessories", "Development", "Education", "Games", "Graphics", "Internet", "Multimedia", "Office", "Science", "Settings", "System"]

    function entryCategories(e) {
        const out = [];
        for (const c of String(e.categories || "").split(/[;,]/)) {
            const m = sm.categoryMap[c.trim()];
            if (m && out.indexOf(m) < 0)
                out.push(m);
        }
        if (out.length === 0)
            out.push("Accessories");
        return out;
    }
    function sidebarItems() {
        const base = [
            { key: "all", label: "All" },
            { key: "favorites", label: "Favorites" },
            { key: "recents", label: "Recently Used" }
        ];
        return base.concat(sm.categoryOrder.map(c => ({ key: c, label: c })));
    }
    // Win7 places: every XDG user dir that exists (fetched from the backend),
    // falling back to the conventional home subfolders.
    property var win7PlaceList: []
    readonly property var win7DefaultPlaces: [
        { label: "Desktop", path: "~/Desktop" },
        { label: "Documents", path: "~/Documents" },
        { label: "Downloads", path: "~/Downloads" },
        { label: "Music", path: "~/Music" },
        { label: "Pictures", path: "~/Pictures" },
        { label: "Public", path: "~/Public" },
        { label: "Templates", path: "~/Templates" },
        { label: "Videos", path: "~/Videos" }
    ]
    function placeGlyph(label) {
        return ({
            Desktop: "\uf108", Documents: "\uf07b", Downloads: "\uf019", Music: "\uf001",
            Pictures: "\uf03e", Public: "\uf0c0", Templates: "\uf1c5", Videos: "\uf03d"
        })[label] || "\uf07b";
    }
    function win7Places() {
        const list = sm.win7PlaceList.length ? sm.win7PlaceList : sm.win7DefaultPlaces;
        return list.map(p => ({ label: p.label, path: p.path, glyph: sm.placeGlyph(p.label) }));
    }
    function openPlace(path) {
        UiState.startMenuOpen = false;
        Quickshell.execDetached(["sh", "-c", "xdg-open " + path]);
    }

    // ── plasma file browser ────────────────────────────────────────────
    readonly property var browsePlaces: [
        { label: "Home", path: "~" },
        { label: "Desktop", path: "~/Desktop" },
        { label: "Documents", path: "~/Documents" },
        { label: "Downloads", path: "~/Downloads" },
        { label: "Music", path: "~/Music" },
        { label: "Pictures", path: "~/Pictures" },
        { label: "Videos", path: "~/Videos" },
        { label: "Trash", path: "~/.local/share/Trash/files" },
        { label: "Network", path: "network:///" },
        { label: "Root", path: "/" }
    ]
    function browseTo(path, push) {
        if (path.indexOf("://") >= 0) {
            UiState.startMenuOpen = false;
            Quickshell.execDetached(["xdg-open", path]);
            return;
        }
        if (push)
            sm.browseHistory = sm.browseHistory.concat([sm.browsePath]);
        browseProc.command = ["python3", sm.filesBackend, "list", path];
        browseProc.running = true;
    }
    function browseBack() {
        if (sm.browseHistory.length === 0)
            return;
        const h = sm.browseHistory.slice();
        const prev = h.pop();
        sm.browseHistory = h;
        sm.browseTo(prev, false);
    }
    function browseUp() {
        if (sm.browseParent && sm.browseParent !== sm.browsePath)
            sm.browseTo(sm.browseParent, true);
    }
    function openEntry(e) {
        if (e.is_dir)
            sm.browseTo(e.path, true);
        else
            Quickshell.execDetached(["xdg-open", e.path]);
    }
    function fmtSize(b) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let v = b, i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    Process {
        id: browseProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    sm.browsePath = o.path || "";
                    sm.browseParent = o.parent || "";
                    sm.browseEntries = o.entries || [];
                } catch (e) {}
            }
        }
    }
    Process {
        id: placesProc
        command: ["python3", sm.filesBackend, "xdg-places"]
        stdout: SplitParser {
            onRead: line => {
                try { sm.win7PlaceList = JSON.parse(line).places || []; } catch (e) {}
            }
        }
    }

    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: sm.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        sm.reveal = visible ? 1 : 0;
        if (visible) {
            sm.targetScreen = Screens.focused();
            sm.query = "";
            sm.side = "all";
            sm.plasmaTab = 0;
            sm.win11AllApps = false;
            sm.browseHistory = [];
            topSearch.clear();
            win7Search.clear();
            searchFocus.restart();
            placesProc.running = true;
        }
    }
    // Focus the search field a beat after opening (after the surface maps).
    Timer { id: searchFocus; interval: 30; onTriggered: { if (topSearch.visible) topSearch.focusSearch(); else if (win7Search.visible) win7Search.focusSearch(); } }

    function launch(entry) {
        if (!entry)
            return;
        UiState.startMenuOpen = false;
        entry.execute();
        recProc.command = ["python3", sm.backend, "record", entry.id];
        recProc.running = true;
    }
    function toggleFav(entry) {
        if (!entry)
            return;
        favProc.command = ["python3", sm.backend, sm.isFavorite(entry.id) ? "unfavorite" : "favorite", entry.id];
        favProc.running = true;
    }
    function clearRecents() {
        clearProc.command = ["python3", sm.backend, "clear-recents"];
        clearProc.running = true;
    }
    function power(cmd) {
        UiState.startMenuOpen = false;
        const c = MenuConfig.power(cmd);
        if (c)
            Quickshell.execDetached(["sh", "-c", c]);
    }

    Process { id: recProc }
    Process { id: favProc }
    Process { id: clearProc }

    // backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea { anchors.fill: parent; onClicked: UiState.startMenuOpen = false }
    }

    Rectangle {
        id: panel
        x: sm.menuX
        y: sm.menuY
        width: sm.menuW
        height: sm.menuH
        radius: 16
        clip: true
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.92)
        border.color: Theme.accent
        border.width: BarConfig.borderWidth
        SequentialAnimation on border.color {
            running: Chrome.animated
            loops: Animation.Infinite
            ColorAnimation { to: Theme.accent2; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
            ColorAnimation { to: Theme.accent; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
        }
        opacity: sm.reveal
        transform: Translate { y: (1 - sm.reveal) * -8 }

        // ── reusable pieces ────────────────────────────────────────────
        component AppIcon: IconImage {
            id: ai
            property var entry
            property int iconSize: 32
            implicitSize: ai.iconSize
            source: Quickshell.iconPath(ai.entry ? ai.entry.icon : "", "application-x-executable")
        }

        component AppRow: Rectangle {
            id: ar
            property var entry
            property int iconSize: 32
            property bool showStar: true
            implicitHeight: ar.entry && ar.entry.comment ? 46 : 38
            radius: sm.isWin7 ? 0 : (sm.isPlasma ? 4 : (sm.isWin11 ? 8 : 10))
            color: arHover.hovered ? sm.rowHover : "transparent"

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sm.launch(ar.entry)
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: sm.isWin7 ? 12 : 10
                anchors.rightMargin: 10
                spacing: 10
                AppIcon { entry: ar.entry; iconSize: ar.iconSize }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: ar.entry ? (ar.entry.name || "") : ""
                        color: Theme.foreground
                        font.pixelSize: sm.isWin7 ? 12 : 13
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!(ar.entry && ar.entry.comment)
                        text: ar.entry ? (ar.entry.comment || "") : ""
                        color: Theme.dim
                        font.pixelSize: sm.isWin7 ? 10 : 11
                        elide: Text.ElideRight
                    }
                }
                Text {
                    visible: ar.showStar && (arHover.hovered || sm.isFavorite(ar.entry ? ar.entry.id : ""))
                    text: sm.isFavorite(ar.entry ? ar.entry.id : "") ? "\uf005" : "\uf006"
                    color: sm.isFavorite(ar.entry ? ar.entry.id : "") ? Theme.warn : Theme.dim
                    font.family: BarConfig.glyphFont
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.toggleFav(ar.entry)
                    }
                }
            }
            HoverHandler { id: arHover }
        }

        component CatRow: Rectangle {
            id: cr
            property string label
            property bool selected
            signal tapped()
            implicitHeight: 30
            radius: sm.isPlasma ? 4 : 8
            color: cr.selected ? sm.selBg : (crHover.hovered ? sm.rowHover : "transparent")
            border.width: cr.selected && !sm.isWin7 ? 1 : 0
            border.color: sm.selBorder
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                text: cr.label
                color: cr.selected ? sm.selectedText : Theme.foreground
                font.pixelSize: 13
                font.bold: cr.selected
            }
            HoverHandler { id: crHover }
            TapHandler { onTapped: cr.tapped() }
        }

        component FavButton: Rectangle {
            id: fb
            property var entry
            implicitWidth: 42
            implicitHeight: 42
            radius: 8
            color: fbHover.hovered ? Theme.alpha(sm.layoutAccent, 0.15) : "transparent"
            AppIcon { entry: fb.entry; iconSize: 26; anchors.centerIn: parent }
            HoverHandler { id: fbHover }
            TapHandler { onTapped: sm.launch(fb.entry) }
        }

        component PinnedTile: Rectangle {
            id: pt
            property var entry
            implicitHeight: 80
            radius: 6
            color: ptHover.hovered ? Theme.alpha(sm.cyanColor, 0.12) : "transparent"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4
                AppIcon { entry: pt.entry; iconSize: 32; Layout.alignment: Qt.AlignHCenter }
                Text {
                    Layout.fillWidth: true
                    text: pt.entry ? (pt.entry.name || "") : ""
                    color: Theme.foreground
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            HoverHandler { id: ptHover }
            TapHandler { onTapped: sm.launch(pt.entry) }
        }

        component PlaceRow: Rectangle {
            id: pr
            property string label
            property string glyph
            property string path
            implicitHeight: 32
            radius: sm.isPlasma ? 4 : 0
            color: prHover.hovered ? Theme.alpha(sm.blueColor, 0.12) : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10
                Text { text: pr.glyph; color: sm.blueColor; font.family: BarConfig.glyphFont; font.pixelSize: 14 }
                Text { text: pr.label; color: Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            }
            HoverHandler { id: prHover }
            TapHandler { onTapped: sm.openPlace(pr.path) }
        }

        component PillButton: Rectangle {
            id: pb
            property string label
            signal tapped()
            implicitWidth: pbText.implicitWidth + 24
            implicitHeight: 24
            radius: 12
            color: pbHover.hovered ? Theme.alpha(sm.layoutAccent, 0.15) : "transparent"
            Text { id: pbText; anchors.centerIn: parent; text: pb.label; color: sm.layoutAccent; font.pixelSize: 11 }
            HoverHandler { id: pbHover }
            TapHandler { onTapped: pb.tapped() }
        }

        component PowerButton: Rectangle {
            id: pw
            property string glyph
            property bool danger: false
            signal tapped()
            implicitWidth: 34
            implicitHeight: 34
            radius: sm.isWin11 ? 17 : (sm.isWin7 || sm.isPlasma ? 4 : 8)
            color: pwHover.hovered
                ? (pw.danger ? Theme.alpha(Theme.err, 0.85) : Theme.alpha(sm.layoutAccent, 0.28))
                : Theme.alpha(sm.layoutAccent, 0.10)
            border.width: 1
            border.color: pw.danger ? Theme.alpha(Theme.err, 0.5) : Theme.alpha(sm.layoutAccent, 0.25)
            Text {
                anchors.centerIn: parent
                text: pw.glyph
                color: pwHover.hovered && pw.danger ? "#ffffff" : Theme.foreground
                font.family: BarConfig.glyphFont
                font.pixelSize: 15
            }
            HoverHandler { id: pwHover }
            TapHandler { onTapped: pw.tapped() }
        }

        component SearchField: Rectangle {
            id: sf
            property alias text: field.text
            property string placeholder: "Search applications\u2026"
            signal edited()
            signal submitted()
            implicitHeight: sm.searchH
            radius: sm.searchRadius
            color: sm.isWin11 ? Theme.alpha(Theme.foreground, 0.06)
                : sm.isWin7 ? Theme.alpha(Theme.background, 0.55)
                : Theme.alpha(sm.layoutAccent, 0.08)
            border.width: 1
            border.color: field.activeFocus ? sm.layoutAccent
                : sm.isWin7 ? Theme.alpha(sm.blueColor, 0.5)
                : Theme.alpha(sm.layoutAccent, 0.25)
            function focusSearch() { field.forceActiveFocus(); }
            function clear() { field.text = ""; }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: Theme.dim
                font.family: BarConfig.glyphFont
                font.pixelSize: 13
            }
            TextField {
                id: field
                anchors.left: parent.left
                anchors.leftMargin: 38
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: sf.placeholder
                placeholderTextColor: Theme.dim
                color: Theme.foreground
                font.pixelSize: 14
                font.family: Theme.fontFamily
                background: Item {}
                selectionColor: sm.layoutAccent
                selectedTextColor: "#000000"
                onTextChanged: sf.edited()
                onAccepted: sf.submitted()
                Keys.onEscapePressed: UiState.startMenuOpen = false
            }
        }

        // ── shell ──────────────────────────────────────────────────────
        // Inset by the panel border width so no full-bleed child (footer /
        // sidebar) paints over the rounded border.
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: panel.border.width
            spacing: 0

            // top search (all but win7)
            SearchField {
                id: topSearch
                visible: !sm.isWin7
                Layout.fillWidth: true
                Layout.leftMargin: sm.searchML
                Layout.rightMargin: sm.searchML
                Layout.topMargin: sm.searchMT
                Layout.bottomMargin: sm.searchMB
                placeholder: sm.isWin11 ? "Search for apps, settings, and documents\u2026" : "Search applications\u2026"
                onEdited: sm.query = text
            }

            // plasma tabs
            RowLayout {
                visible: sm.isPlasma
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 0
                Repeater {
                    model: [
                        { label: "Applications", tab: 0 },
                        { label: "Computer", tab: 1 },
                        { label: "Recently Used", tab: 2 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        color: sm.plasmaTab === modelData.tab ? Theme.alpha(sm.blueColor, 0.14) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Theme.foreground
                            font.pixelSize: 12
                            font.bold: sm.plasmaTab === modelData.tab
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: sm.plasmaTab === modelData.tab ? sm.blueColor : "transparent"
                        }
                        TapHandler {
                            onTapped: {
                                sm.plasmaTab = modelData.tab;
                                if (modelData.tab === 1 && sm.browseEntries.length === 0)
                                    sm.browseTo("~", false);
                            }
                        }
                    }
                }
            }
            Rectangle {
                visible: sm.isPlasma
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.alpha(sm.blueColor, 0.2)
            }

            // main area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── whisker: sidebar | favourites + apps | recents ──────
                RowLayout {
                    anchors.fill: parent
                    visible: sm.isWhisker
                    spacing: 0

                    Rectangle {
                        Layout.preferredWidth: MenuConfig.sidebarWidth
                        Layout.fillHeight: true
                        color: Theme.alpha(sm.layoutAccent, 0.05)
                        ListView {
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            model: sm.sidebarItems()
                            spacing: 1
                            delegate: CatRow {
                                width: ListView.view.width
                                label: modelData.label
                                selected: sm.side === modelData.key
                                onTapped: sm.side = modelData.key
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        Rectangle {
                            visible: sm.favoritesEntries().length > 0
                            Layout.fillWidth: true
                            Layout.margins: 8
                            implicitHeight: 84
                            radius: 12
                            color: Theme.alpha(sm.layoutAccent, 0.07)
                            border.width: 1
                            border.color: Theme.alpha(sm.layoutAccent, 0.25)
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6
                                Text { text: "Favorites"; color: sm.layoutAccent; font.pixelSize: 11; font.bold: true }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: sm.favoritesEntries()
                                        delegate: FavButton { entry: modelData }
                                    }
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.margins: 4
                            clip: true
                            model: sm.shown()
                            spacing: 1
                            delegate: AppRow { width: ListView.view.width; entry: modelData }
                        }
                    }

                    Rectangle {
                        visible: MenuConfig.showRecents
                        Layout.preferredWidth: MenuConfig.recentsWidth
                        Layout.fillHeight: true
                        color: Theme.alpha(sm.layoutAccent, 0.05)
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 8
                                Layout.topMargin: 10
                                Layout.bottomMargin: 4
                                spacing: 6
                                Text { text: "Recently Used"; color: Theme.dim; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true }
                                PillButton { label: "Clear"; onTapped: sm.clearRecents() }
                            }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 4
                                clip: true
                                model: sm.recommendedEntries()
                                spacing: 1
                                delegate: AppRow { width: ListView.view.width; entry: modelData; iconSize: 26; showStar: false }
                            }
                        }
                    }
                }

                // ── win7: apps (+ All Programs) | places + search ───────
                RowLayout {
                    anchors.fill: parent
                    visible: sm.isWin7
                    spacing: 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        Rectangle {
                            visible: sm.favoritesEntries().length > 0
                            Layout.fillWidth: true
                            implicitHeight: 66
                            color: "transparent"
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.topMargin: 8
                                spacing: 4
                                Text { text: "Favorites"; color: sm.blueColor; font.pixelSize: 11; font.bold: true }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: sm.favoritesEntries()
                                        delegate: FavButton { entry: modelData }
                                    }
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: sm.shown()
                            spacing: 0
                            delegate: AppRow { width: ListView.view.width; entry: modelData }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            color: allHover.hovered ? Theme.alpha(sm.blueColor, 0.12) : "transparent"
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Theme.alpha(sm.blueColor, 0.2) }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                Text { text: "All Programs"; color: Theme.foreground; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                                Text { text: "\u25b8"; color: Theme.dim; font.pixelSize: 11 }
                            }
                            HoverHandler { id: allHover }
                            TapHandler { onTapped: sm.side = "all" }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.fillHeight: true
                        color: Theme.alpha(sm.blueColor, 0.04)
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: 6
                                clip: true
                                model: sm.win7Places()
                                spacing: 0
                                delegate: PlaceRow { width: ListView.view.width; label: modelData.label; glyph: modelData.glyph; path: modelData.path }
                            }
                            SearchField {
                                id: win7Search
                                Layout.fillWidth: true
                                placeholder: "Search applications\u2026"
                                onEdited: sm.query = text
                            }
                        }
                    }
                }

                // ── win11: pinned tiles + recommended / all apps ────────
                Item {
                    anchors.fill: parent
                    visible: sm.isWin11

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        visible: !sm.win11AppsView

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.topMargin: 8
                            Layout.bottomMargin: 2
                            spacing: 8
                            Text { text: "Pinned"; color: Theme.foreground; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                            PillButton { label: "All apps  \u25b8"; onTapped: sm.win11AllApps = true }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            implicitHeight: pinnedGrid.implicitHeight + 16
                            radius: 8
                            color: Theme.alpha(Theme.foreground, 0.04)
                            border.width: 1
                            border.color: Theme.alpha(Theme.foreground, 0.08)
                            GridLayout {
                                id: pinnedGrid
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                columns: 6
                                columnSpacing: 4
                                rowSpacing: 4
                                Repeater {
                                    model: sm.pinnedEntries()
                                    delegate: PinnedTile { Layout.fillWidth: true; entry: modelData }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.topMargin: 10
                            Layout.bottomMargin: 2
                            spacing: 8
                            Text { text: "Recommended"; color: Theme.foreground; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                            PillButton { label: "More  \u25b8" }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.bottomMargin: 10
                            color: Theme.alpha(Theme.foreground, 0.03)
                            ListView {
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: sm.recommendedEntries()
                                spacing: 1
                                delegate: AppRow { width: ListView.view.width; entry: modelData; showStar: false }
                            }
                        }
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: sm.win11AppsView
                        clip: true
                        model: sm.shown()
                        spacing: 2
                        delegate: AppRow { width: ListView.view.width; entry: modelData }
                    }
                }

                // ── plasma: applications / computer / recents ──────────
                Item {
                    anchors.fill: parent
                    visible: sm.isPlasma

                    RowLayout {
                        anchors.fill: parent
                        visible: sm.plasmaTab === 0
                        spacing: 0
                        Rectangle {
                            Layout.preferredWidth: MenuConfig.sidebarWidth
                            Layout.fillHeight: true
                            color: Theme.alpha(sm.blueColor, 0.06)
                            ListView {
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: sm.sidebarItems()
                                spacing: 1
                                delegate: CatRow {
                                    width: ListView.view.width
                                    label: modelData.label
                                    selected: sm.side === modelData.key
                                    onTapped: sm.side = modelData.key
                                }
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.margins: 4
                            clip: true
                            model: sm.shown()
                            spacing: 1
                            delegate: AppRow { width: ListView.view.width; entry: modelData }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        visible: sm.plasmaTab === 1
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            spacing: 6
                            PillButton { label: "\u2190"; onTapped: sm.browseBack() }
                            PillButton { label: "\u2191"; onTapped: sm.browseUp() }
                            Text { text: sm.browsePath; color: Theme.dim; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 0
                            Rectangle {
                                Layout.preferredWidth: 150
                                Layout.fillHeight: true
                                color: Theme.alpha(sm.blueColor, 0.05)
                                ListView {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    model: sm.browsePlaces
                                    spacing: 1
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: ListView.view.width
                                        implicitHeight: 30
                                        radius: 4
                                        color: bp2Hover.hovered ? Theme.alpha(sm.blueColor, 0.12) : "transparent"
                                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 12; text: modelData.label; color: Theme.foreground; font.pixelSize: 12 }
                                        HoverHandler { id: bp2Hover }
                                        TapHandler { onTapped: sm.browseTo(modelData.path, false) }
                                    }
                                }
                            }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 4
                                clip: true
                                model: sm.browseEntries
                                spacing: 1
                                delegate: Rectangle {
                                    id: frow
                                    required property var modelData
                                    width: ListView.view.width
                                    implicitHeight: 30
                                    radius: 4
                                    color: frHover.hovered ? Theme.alpha(sm.blueColor, 0.12) : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        Text { text: frow.modelData.is_dir ? "\uf07b" : "\uf15b"; color: frow.modelData.is_dir ? Theme.warn : sm.blueColor; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
                                        Text { text: frow.modelData.name; color: Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Text { visible: !frow.modelData.is_dir; text: sm.fmtSize(frow.modelData.size); color: Theme.dim; font.pixelSize: 10 }
                                    }
                                    HoverHandler { id: frHover }
                                    TapHandler { onTapped: sm.openEntry(frow.modelData) }
                                }
                            }
                        }
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: sm.plasmaTab === 2
                        clip: true
                        model: sm.recentsEntries()
                        spacing: 1
                        delegate: AppRow { width: ListView.view.width; entry: modelData }
                    }
                }
            }

            // ── footer: user | hyprtk-menu, settings + power ───────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                color: sm.footerBg
                // Match the panel's rounded bottom corners (minus the border).
                bottomLeftRadius: panel.radius - panel.border.width
                bottomRightRadius: panel.radius - panel.border.width
                Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: sm.footerBorder }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 13
                            color: Theme.alpha(sm.layoutAccent, 0.22)
                            Text { anchors.centerIn: parent; text: "\uf007"; color: sm.layoutAccent; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
                        }
                        Text { text: sm.username; color: Theme.foreground; font.pixelSize: 12 }
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        spacing: 8
                        Text { text: "hyprtk-menu"; color: Theme.dim; font.pixelSize: 12; font.italic: true }
                        PowerButton { glyph: "\uf013"; onTapped: { UiState.startMenuOpen = false; UiState.settingsOpen = true; } }
                        PowerButton { glyph: "\uf023"; onTapped: sm.power("lock") }
                        PowerButton { glyph: "\uf08b"; onTapped: sm.power("logout") }
                        PowerButton { glyph: "\uf021"; danger: true; onTapped: sm.power("reboot") }
                        PowerButton { glyph: "\uf011"; danger: true; onTapped: sm.power("shutdown") }
                        Text { text: "\u2b0c"; color: Theme.dim; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "startmenu"
        function toggle() { UiState.startMenuOpen = !UiState.startMenuOpen; }
        function open() { UiState.startMenuOpen = true; }
        function close() { UiState.startMenuOpen = false; }
    }
}
