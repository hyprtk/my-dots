// Mission Center-style system monitor dialog, opened by left-clicking the
// sysmon module. A layer-shell panel floated above the bar with a sidebar of
// resource pages (CPU / Memory / Disks / Network / GPU) and live QML graphs.
//
// All colours come from the live theme, so the panel matches the bar.
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

    visible: UiState.sysMonitorOpen
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    // Open under the sysmon module on its monitor (registered by the module),
    // else the focused monitor.
    property var targetScreen: null
    screen: Screens.byName(BarAnchors.sysmonScreen) || targetScreen

    readonly property real screenW: win.screen ? win.screen.width : 0
    readonly property var insets: BarGeom.insets(win.screenW)
    // Left edge under the sysmon module, clamped inside the bar's extent so the
    // panel never spills past the bar/screen boundary.
    readonly property real leftMargin: Math.max(
        win.insets.left,
        Math.min(win.insets.left + Math.max(0, BarAnchors.sysmonX),
                 win.screenW - win.insets.right - win.implicitWidth))

    anchors.top: BarConfig.barPosition === "top"
    anchors.bottom: BarConfig.barPosition === "bottom"
    anchors.left: true
    margins.top: BarConfig.barPosition === "top" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.left: win.leftMargin
    implicitWidth: 920
    implicitHeight: 600

    IpcHandler {
        target: "sysmon"
        function toggle() { UiState.sysMonitorOpen = !UiState.sysMonitorOpen; }
        function open() { UiState.sysMonitorOpen = true; }
        function close() { UiState.sysMonitorOpen = false; }
    }

    // Drive the backend only while the dialog is open.
    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        MonitorData.active = visible;
        reveal = visible ? 1 : 0;
        if (visible)
            targetScreen = Screens.focused();
    }

    readonly property var allPages: [
        { key: "cpu", glyph: "\uf2db", label: "CPU" },        // fa-microchip
        { key: "memory", glyph: "\uefc5", label: "Memory" },  // fa-memory
        { key: "disks", glyph: String.fromCodePoint(0xf02ca), label: "Disks" },// md-harddisk
        { key: "network", glyph: "\uf1eb", label: "Network" },// fa-wifi
        { key: "gpu", glyph: "\uf03d", label: "GPU" },        // fa-video-camera
        { key: "apps", glyph: "\uf0ae", label: "Apps" }       // fa-tasks
    ]
    readonly property var enabledPages: {
        const want = MonitorData.pageList || [];
        const list = win.allPages.filter(p => want.indexOf(p.key) >= 0);
        return list.length ? list : win.allPages;
    }
    property int activeIndex: 0
    readonly property string activeKey: (win.enabledPages[win.activeIndex] || win.enabledPages[0] || {}).key || "cpu"
    readonly property int stackIndex: Math.max(0, win.allPages.findIndex(p => p.key === win.activeKey))

    // Keep the backend's active page in sync (gates the expensive Apps walk),
    // and lazily read the cached DIMM slots on first arrival at Memory.
    onActiveKeyChanged: {
        MonitorData.activePage = win.activeKey;
        if (win.activeKey === "memory" && !MonitorData.dimmLoaded)
            MonitorData.loadDimm(false);
    }
    Component.onCompleted: MonitorData.activePage = win.activeKey

    // ── Apps page state ────────────────────────────────────────────────
    readonly property var appsViews: [
        { key: "user-apps", label: "User apps" },
        { key: "system-apps", label: "System apps" },
        { key: "user-procs", label: "User processes" },
        { key: "system-procs", label: "System processes" }
    ]
    property string appsKey: "user-apps"
    property int selPid: -1
    property string selName: ""
    property string appsMsg: ""
    property bool confirmOpen: false
    property bool confirmForce: false

    function bucketRows(key) {
        const u = MonitorData.uid;
        return (MonitorData.apps || []).filter(r => {
            if (key === "user-apps")
                return r.uid === u && r.is_app;
            if (key === "system-apps")
                return r.uid !== u && r.is_app;
            if (key === "user-procs")
                return r.uid === u;
            return r.uid !== u;
        }).slice(0, 250);
    }
    function fmtMem(gb) {
        if (!gb || gb <= 0)
            return "--";
        return gb >= 1 ? gb.toFixed(2) + " GB" : (gb * 1024).toFixed(0) + " MB";
    }
    function selectRow(r) {
        win.selPid = r.pid;
        win.selName = r.name;
    }
    function toast(msg) {
        win.appsMsg = msg;
        toastTimer.restart();
    }
    function launchSelected() {
        if (win.selPid < 0) {
            win.toast("Select a process to launch");
            return;
        }
        win.runProc(["launch", String(win.selPid)]);
    }
    function askKill(force) {
        if (win.selPid < 0) {
            win.toast("Select a process to kill");
            return;
        }
        win.confirmForce = force;
        win.confirmOpen = true;
    }
    function confirmKill() {
        win.confirmOpen = false;
        const args = ["kill", String(win.selPid)].concat(win.confirmForce ? ["--force"] : []);
        win.runProc(args);
    }
    function runProc(args) {
        action.command = ["python3", MonitorData.actionBackend].concat(args);
        action.running = true;
    }

    Timer {
        id: toastTimer
        interval: 3000
        onTriggered: win.appsMsg = ""
    }

    Process {
        id: action
        onExited: (exitCode, exitStatus) => {
            win.toast(exitCode === 0 ? "Done" : "Failed (permission?)");
        }
    }

    // Per-page graph colours, matching the waybar-era pywal assignments.
    function pageColor(key) {
        const map = { cpu: 5, memory: 4, disks: 3, network: 2, gpu: 6 };
        const n = map[key] || 5;
        return Theme.walColor(n, Theme.accent);
    }
    function levelColor(pct) {
        if (pct >= 90)
            return Theme.err;
        if (pct >= 70)
            return Theme.warn;
        return Theme.accent;
    }
    function stat(expr, fallback) {
        return MonitorData.ready ? expr : (fallback || "--");
    }

    // ── reusable pieces ────────────────────────────────────────────────
    component GraphCard: ColumnLayout {
        id: gcard
        property string title: ""
        property string value: ""
        property var values: []
        property color graphColor: Theme.accent
        property real scale: 0
        property int graphHeight: 46
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
            Layout.fillWidth: true
            Text { text: gcard.title; color: Theme.dim; font.pixelSize: 11; Layout.fillWidth: true }
            Text { text: gcard.value; color: Theme.foreground; font.pixelSize: 11 }
        }
        Sparkline {
            Layout.fillWidth: true
            Layout.preferredHeight: gcard.graphHeight
            values: gcard.values
            color: gcard.graphColor
            scale: gcard.scale
            maxPoints: MonitorData.histLen
        }
    }

    component Readout: RowLayout {
        id: ro
        property string glyph: ""
        property string label: ""
        property string value: ""
        spacing: 6
        Text { text: ro.glyph; color: Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: 12 }
        Text { text: ro.label; color: Theme.dim; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: ro.value; color: Theme.foreground; font.pixelSize: 11 }
    }

    component SideButton: Rectangle {
        id: sb
        property string glyph: ""
        property string label: ""
        property bool active: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 8
        color: sb.active
            ? Theme.alpha(Theme.accent, 0.85)
            : (hov.hovered ? Theme.alpha(Theme.accent2, 0.15) : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8
            Text { text: sb.glyph; color: sb.active ? "#000000" : Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
            Text { text: sb.label; color: sb.active ? "#000000" : Theme.foreground; font.pixelSize: 12; Layout.fillWidth: true }
        }
        HoverHandler { id: hov }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.activated()
        }
    }

    component CoreRow: RowLayout {
        id: cr
        property int core: 0
        property real pct: 0
        Layout.fillWidth: true
        spacing: 8
        Text { text: "Core " + cr.core; color: Theme.dim; font.pixelSize: 10; Layout.preferredWidth: 52 }
        Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: Theme.alpha(Theme.dim, 0.25)
            Rectangle {
                width: parent.width * Math.min(Math.max(cr.pct / 100, 0), 1)
                height: parent.height
                radius: 3
                color: win.levelColor(cr.pct)
            }
        }
        Text {
            text: Math.round(cr.pct) + "%"
            color: Theme.foreground
            font.pixelSize: 10
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
        }
    }

    component DriveCard: Rectangle {
        id: dc
        property var drive: ({})
        property bool selected: false
        Layout.fillWidth: true
        implicitHeight: 56
        radius: 8
        color: dc.selected ? Theme.alpha(Theme.accent, 0.22) : Theme.alpha(Theme.background, 0.5)
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, dc.selected ? 0.6 : 0.18)

        readonly property real usedPct: {
            const denom = (dc.drive.used_b || 0) + (dc.drive.free_b || 0);
            return denom > 0 ? 100 * (dc.drive.used_b || 0) / denom : 0;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Text { text: dc.drive.glyph || ""; color: Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: 12 }
                Text { text: dc.drive.type_label || ""; color: Theme.foreground; font.pixelSize: 10; Layout.fillWidth: true }
                Text { text: dc.drive.size_b > 0 ? MonitorData.fmtBytes(dc.drive.size_b) : "\u2014"; color: Theme.dim; font.pixelSize: 10 }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Rectangle {
                    Layout.fillWidth: true
                    height: 5
                    radius: 3
                    color: Theme.alpha(Theme.dim, 0.25)
                    Rectangle {
                        width: parent.width * Math.min(Math.max(dc.usedPct / 100, 0), 1)
                        height: parent.height
                        radius: 3
                        color: win.levelColor(dc.usedPct)
                    }
                }
                Text {
                    text: dc.drive.mounted ? MonitorData.fmtBytes(dc.drive.free_b) + " free"
                        : (dc.drive.size_b === 0 ? "No media" : "not mounted")
                    color: Theme.dim
                    font.pixelSize: 9
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                MonitorData.selectedDrive = dc.drive.name;
                MonitorData.diskUsageHist = [];
            }
        }
    }

    component AppRow: Rectangle {
        id: ar
        property var entry: ({})
        property bool selected: false
        Layout.fillWidth: true
        implicitHeight: 24
        radius: 4
        color: ar.selected ? Theme.alpha(Theme.accent, 0.3)
            : (arHover.hovered ? Theme.alpha(Theme.accent2, 0.1) : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8
            Text {
                text: ar.entry.name || ""
                color: Theme.foreground
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: (ar.entry.cpu || 0).toFixed(1) + "%"
                color: Theme.dim
                font.pixelSize: 11
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignRight
            }
            Text {
                text: win.fmtMem(ar.entry.mem || 0)
                color: Theme.dim
                font.pixelSize: 11
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignRight
            }
        }
        HoverHandler { id: arHover }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: win.selectRow(ar.entry)
        }
    }

    component DimmCard: Rectangle {
        id: dcard
        property var slot: ({})
        implicitWidth: 96
        implicitHeight: 54
        radius: 8
        color: Theme.alpha(Theme.accent2, dcard.slot.populated ? 0.14 : 0.05)
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, dcard.slot.populated ? 0.4 : 0.15)
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                Text {
                    text: "\uefc5"
                    color: dcard.slot.populated ? Theme.accent : Theme.dim
                    font.family: BarConfig.glyphFont
                    font.pixelSize: 13
                }
                Text {
                    text: dcard.slot.populated ? Math.round(dcard.slot.size_gb || 0) + " GB" : "Empty"
                    color: dcard.slot.populated ? Theme.foreground : Theme.dim
                    font.pixelSize: 11
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: dcard.slot.locator || ""
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    component ActionButton: Rectangle {
        id: ab
        property string label: ""
        signal clicked()
        implicitHeight: 28
        implicitWidth: abText.implicitWidth + 24
        radius: 6
        color: abHover.hovered ? Theme.alpha(Theme.accent2, 0.25) : Theme.alpha(Theme.accent2, 0.12)
        Text {
            id: abText
            anchors.centerIn: parent
            text: ab.label
            color: Theme.foreground
            font.pixelSize: 11
        }
        HoverHandler { id: abHover }
        TapHandler { onTapped: ab.clicked() }
    }

    component InterfaceRow: RowLayout {
        id: ir
        property var iface: ({})
        Layout.fillWidth: true
        spacing: 10
        Text { text: ir.iface.glyph || ""; color: Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: 13 }
        Text { text: ir.iface.name || ""; color: Theme.foreground; font.pixelSize: 11; Layout.preferredWidth: 80 }
        Text { text: ir.iface.type || ""; color: Theme.dim; font.pixelSize: 11; Layout.preferredWidth: 80 }
        Text { text: ir.iface.ip || "\u2014"; color: Theme.foreground; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: "\uf063"; color: Theme.accent2; font.family: BarConfig.glyphFont; font.pixelSize: 10 }
        Text { text: MonitorData.fmtRate(ir.iface.down_bps || 0); color: Theme.foreground; font.pixelSize: 11 }
        Text { text: "\uf062"; color: Theme.warn; font.family: BarConfig.glyphFont; font.pixelSize: 10 }
        Text { text: MonitorData.fmtRate(ir.iface.up_bps || 0); color: Theme.foreground; font.pixelSize: 11 }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.96, Theme.opacity))
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── header ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text { text: "System Monitor"; color: Theme.accent; font.bold: true; font.pixelSize: 16; Layout.fillWidth: true }
                Text {
                    text: "\u00d7"
                    color: Theme.dim
                    font.pixelSize: 18
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UiState.sysMonitorOpen = false
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // ── sidebar ────────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 132
                    Layout.minimumWidth: 132
                    Layout.maximumWidth: 132
                    Layout.fillHeight: true
                    spacing: 3
                    Repeater {
                        model: win.enabledPages
                        delegate: SideButton {
                            required property var modelData
                            required property int index
                            glyph: modelData.glyph
                            label: modelData.label
                            active: win.activeIndex === index
                            onActivated: win.activeIndex = index
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ── pages ──────────────────────────────────────────────
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    currentIndex: win.stackIndex

                    // CPU ───────────────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: cpuCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: cpuCol
                            width: parent.width
                            spacing: 10
                            GraphCard {
                                title: "CPU usage (all threads)"
                                value: win.stat(Math.round(MonitorData.cpu.overall || 0) + "%", "--")
                                values: MonitorData.cpuHist
                                graphColor: win.pageColor("cpu")
                                scale: 100
                            }
                            GraphCard {
                                title: "Temperature"
                                value: MonitorData.cpu.temp_c !== undefined && MonitorData.cpu.temp_c !== null
                                    ? Math.round(MonitorData.cpu.temp_c) + "\u00b0C" : "--"
                                values: MonitorData.cpuTempHist
                                graphColor: win.pageColor("cpu")
                                graphHeight: 40
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 28
                                rowSpacing: 4
                                Readout { glyph: "\uf0e4"; label: "Load average"; value: win.stat(MonitorData.cpu.load ? MonitorData.cpu.load.map(v => v.toFixed(2)).join(" ") : "--") }
                                Readout { glyph: "\uf0ae"; label: "Processes"; value: win.stat(String(MonitorData.cpu.processes)) }
                                Readout { glyph: "\uf1b3"; label: "Threads"; value: win.stat(String(MonitorData.cpu.threads)) }
                                Readout { glyph: "\uf017"; label: "Uptime"; value: MonitorData.ready ? MonitorData.fmtUptime(MonitorData.cpu.uptime_s) : "--" }
                                Readout { glyph: "\uf2db"; label: "Current frequency"; value: win.stat(MonitorData.cpu.freq_mhz ? MonitorData.cpu.freq_mhz.toLocaleString() + " MHz" : "--") }
                                Readout { glyph: "\uf2db"; label: "Max frequency"; value: win.stat(MonitorData.cpu.freq_max_mhz ? MonitorData.cpu.freq_max_mhz.toLocaleString() + " MHz" : "--") }
                                Readout { glyph: "\uf2c9"; label: "CPU temperature"; value: MonitorData.cpu.temp_c !== undefined && MonitorData.cpu.temp_c !== null ? Math.round(MonitorData.cpu.temp_c) + "\u00b0C" : "--" }
                                Readout { glyph: "\uf2db"; label: "Model"; value: win.stat(MonitorData.cpu.model || "--") }
                            }
                            Text { text: "Cores / Threads"; color: Theme.dim; font.pixelSize: 11 }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 2
                                Repeater {
                                    model: MonitorData.cpu.cores || []
                                    delegate: CoreRow {
                                        required property var modelData
                                        required property int index
                                        core: index
                                        pct: modelData
                                    }
                                }
                            }
                        }
                    }

                    // Memory ────────────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: memCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: memCol
                            width: parent.width
                            spacing: 10
                            GraphCard {
                                title: "Memory usage"
                                value: win.stat(Math.round(MonitorData.mem.used_pct || 0) + "%", "--")
                                values: MonitorData.memHist
                                graphColor: win.pageColor("memory")
                                scale: 100
                            }
                            GraphCard {
                                title: "Swap"
                                value: win.stat(Math.round(MonitorData.mem.swap_pct || 0) + "%", "--")
                                values: MonitorData.swapHist
                                graphColor: win.pageColor("memory")
                                graphHeight: 40
                                scale: 100
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 28
                                rowSpacing: 4
                                Readout { glyph: "\uefc5"; label: "Used";                                 value: win.stat((MonitorData.mem.used_gb || 0).toFixed(1) + " / " + (MonitorData.mem.total_gb || 0).toFixed(1) + " GB") }
                                Readout { glyph: "\uefc5"; label: "Total"; value: win.stat((MonitorData.mem.total_gb || 0).toFixed(1) + " GB") }
                                Readout { glyph: "\uefc5"; label: "Available"; value: win.stat((MonitorData.mem.avail_gb || 0).toFixed(1) + " GB") }
                                Readout { glyph: "\uf187"; label: "Buffers"; value: win.stat((MonitorData.mem.buffers_gb || 0).toFixed(2) + " GB") }
                                Readout { glyph: "\uf07c"; label: "Cached"; value: win.stat((MonitorData.mem.cached_gb || 0).toFixed(2) + " GB") }
                                Readout { glyph: "\uf0ec"; label: "Swap used"; value: win.stat((MonitorData.mem.swap_used_gb || 0).toFixed(2) + " GB") }
                                Readout { glyph: "\uf0ec"; label: "Swap total"; value: win.stat((MonitorData.mem.swap_total_gb || 0).toFixed(2) + " GB") }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                Text { text: "Memory Slots"; color: Theme.dim; font.pixelSize: 11; Layout.fillWidth: true }
                                Text {
                                    visible: MonitorData.dimmLoaded
                                    text: MonitorData.dimmPopulated() + " populated \u00b7 " + Math.round(MonitorData.dimmTotalGb()) + " GB"
                                    color: Theme.foreground
                                    font.pixelSize: 11
                                }
                                ActionButton { label: "Refresh"; onClicked: MonitorData.loadDimm(true) }
                            }
                            Text {
                                visible: MonitorData.dimmStatus.length > 0
                                text: MonitorData.dimmStatus
                                color: Theme.dim
                                font.pixelSize: 10
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: MonitorData.dimmSlots
                                    delegate: DimmCard {
                                        required property var modelData
                                        slot: modelData
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    // Disks ──────────────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: diskCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: diskCol
                            width: parent.width
                            spacing: 10
                            GraphCard {
                                title: "Disk usage"
                                value: {
                                    const d = MonitorData.selectedDriveInfo();
                                    return win.stat((d ? d.name + " " : "") + Math.round(MonitorData.diskUsageHist.length ? MonitorData.diskUsageHist[MonitorData.diskUsageHist.length - 1] : 0) + "%");
                                }
                                values: MonitorData.diskUsageHist
                                graphColor: win.pageColor("disks")
                                graphHeight: 40
                                scale: 100
                            }
                            GraphCard {
                                title: "Read rate"
                                value: win.stat(MonitorData.fmtRate(MonitorData.deviceRate(MonitorData.selectedDrive).read), "--")
                                values: MonitorData.diskReadHist
                                graphColor: win.pageColor("disks")
                                graphHeight: 28
                            }
                            GraphCard {
                                title: "Write rate"
                                value: win.stat(MonitorData.fmtRate(MonitorData.deviceRate(MonitorData.selectedDrive).write), "--")
                                values: MonitorData.diskWriteHist
                                graphColor: win.pageColor("disks")
                                graphHeight: 28
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 28
                                rowSpacing: 4
                                Readout {
                                    glyph: String.fromCodePoint(0xf02ca); label: "Used"
                                    value: {
                                        const d = MonitorData.selectedDriveInfo();
                                        return win.stat(d && d.used_b ? MonitorData.fmtBytes(d.used_b) + " / " + MonitorData.fmtBytes(d.size_b) : "not mounted");
                                    }
                                }
                                Readout { glyph: "\uf0ec"; label: "Total I/O"; value: win.stat(MonitorData.fmtRate((MonitorData.disk.read_bps || 0) + (MonitorData.disk.write_bps || 0)), "--") }
                            }
                            Text { text: "Drives"; color: Theme.dim; font.pixelSize: 11 }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8
                                Repeater {
                                    model: MonitorData.drives
                                    delegate: DriveCard {
                                        required property var modelData
                                        drive: modelData
                                        selected: modelData.name === MonitorData.selectedDrive
                                    }
                                }
                            }
                        }
                    }

                    // Network ────────────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: netCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: netCol
                            width: parent.width
                            spacing: 10
                            GraphCard {
                                title: "Download"
                                value: win.stat(MonitorData.fmtRate(MonitorData.net.down_bps || 0), "--")
                                values: MonitorData.netDownHist
                                graphColor: win.pageColor("network")
                                graphHeight: 40
                            }
                            GraphCard {
                                title: "Upload"
                                value: win.stat(MonitorData.fmtRate(MonitorData.net.up_bps || 0), "--")
                                values: MonitorData.netUpHist
                                graphColor: win.pageColor("network")
                                graphHeight: 32
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 28
                                rowSpacing: 4
                                Readout { glyph: "\uf1eb"; label: "Interface"; value: win.stat(MonitorData.net.iface || "--") }
                                Readout { glyph: "\uf1eb"; label: "Type"; value: win.stat(MonitorData.net.type || "--") }
                                Readout { glyph: "\uf1eb"; label: "IP address"; value: win.stat(MonitorData.net.ip || "--") }
                                Readout { glyph: "\uf0ab"; label: "Download"; value: win.stat(MonitorData.fmtRate(MonitorData.net.down_bps || 0), "--") }
                                Readout { glyph: "\uf0aa"; label: "Upload"; value: win.stat(MonitorData.fmtRate(MonitorData.net.up_bps || 0), "--") }
                            }
                            Text { text: "Interfaces"; color: Theme.dim; font.pixelSize: 11 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Repeater {
                                    model: MonitorData.net.all || []
                                    delegate: InterfaceRow {
                                        required property var modelData
                                        iface: modelData
                                    }
                                }
                            }
                        }
                    }

                    // GPU ────────────────────────────────────────────────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: gpuCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: gpuCol
                            width: parent.width
                            spacing: 10
                            GraphCard {
                                title: "GPU usage"
                                value: MonitorData.gpu && MonitorData.gpu.util_pct !== null && MonitorData.gpu.util_pct !== undefined
                                    ? Math.round(MonitorData.gpu.util_pct) + "%" : "--"
                                values: MonitorData.gpuUtilHist
                                graphColor: win.pageColor("gpu")
                                graphHeight: 48
                                scale: 100
                            }
                            GraphCard {
                                title: "VRAM"
                                value: {
                                    const g = MonitorData.gpu;
                                    if (!g)
                                        return "--";
                                    if (g.vram_total_gb && g.vram_total_gb > 0)
                                        return (g.vram_used_gb || 0).toFixed(1) + " / " + g.vram_total_gb.toFixed(1) + " GB";
                                    return "shared";
                                }
                                values: MonitorData.gpuVramHist
                                graphColor: win.pageColor("gpu")
                                graphHeight: 32
                                scale: 100
                            }
                            Text {
                                visible: MonitorData.gpuStatic && MonitorData.gpuStatic.model
                                text: MonitorData.gpuStatic ? (MonitorData.gpuStatic.model || "") : ""
                                color: Theme.foreground
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                visible: text.length > 0
                                text: {
                                    const g = MonitorData.gpuStatic;
                                    if (!g)
                                        return "";
                                    const parts = [];
                                    if (g.manufacturer)
                                        parts.push(g.manufacturer);
                                    if (g.units)
                                        parts.push(g.units + " compute units");
                                    if (g.max_clock)
                                        parts.push(g.max_clock.toLocaleString() + " MHz max");
                                    return parts.join(" \u00b7 ");
                                }
                                color: Theme.dim
                                font.pixelSize: 11
                            }
                            Text {
                                visible: MonitorData.ready && !MonitorData.gpu
                                text: "GPU monitoring unavailable"
                                color: Theme.dim
                                font.pixelSize: 11
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 28
                                rowSpacing: 4
                                Readout { glyph: "\uf03d"; label: "Utilization"; value: MonitorData.gpu && MonitorData.gpu.util_pct !== null && MonitorData.gpu.util_pct !== undefined ? Math.round(MonitorData.gpu.util_pct) + "%" : "--" }
                                Readout { glyph: "\uf03d"; label: "VRAM"; value: {
                                    const g = MonitorData.gpu;
                                    if (!g)
                                        return "--";
                                    return (g.vram_total_gb && g.vram_total_gb > 0) ? (g.vram_used_gb || 0).toFixed(1) + " / " + g.vram_total_gb.toFixed(1) + " GB" : "shared (system RAM)";
                                } }
                                Readout { glyph: "\uf2c9"; label: "Temperature"; value: MonitorData.gpu && MonitorData.gpu.temps && MonitorData.gpu.temps.edge !== undefined ? Math.round(MonitorData.gpu.temps.edge) + "\u00b0C" : (MonitorData.gpu && MonitorData.gpu.temps && MonitorData.gpu.temps.temp !== undefined ? Math.round(MonitorData.gpu.temps.temp) + "\u00b0C" : "--") }
                                Readout { glyph: "\uf0e7"; label: "Power"; value: MonitorData.gpu && MonitorData.gpu.power_w !== null && MonitorData.gpu.power_w !== undefined ? Math.round(MonitorData.gpu.power_w) + " W" : "--" }
                                Readout { glyph: "\uf021"; label: "Fan"; value: MonitorData.gpu && MonitorData.gpu.fan_pct !== null && MonitorData.gpu.fan_pct !== undefined ? Math.round(MonitorData.gpu.fan_pct) + "%" : (MonitorData.gpu && MonitorData.gpu.fan_rpm ? MonitorData.gpu.fan_rpm + " RPM" : "--") }
                            }
                        }
                    }

                    // Apps ───────────────────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Flickable {
                            anchors.fill: parent
                            contentHeight: appsCol.implicitHeight
                            clip: true
                            ColumnLayout {
                                id: appsCol
                                width: parent.width
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: win.appsViews
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 26
                                            radius: 6
                                            color: win.appsKey === modelData.key
                                                ? Theme.alpha(Theme.accent, 0.85)
                                                : Theme.alpha(Theme.accent2, 0.12)
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: win.appsKey === modelData.key ? "#000000" : Theme.foreground
                                                font.pixelSize: 11
                                            }
                                            TapHandler {
                                                onTapped: {
                                                    win.appsKey = modelData.key;
                                                    win.selPid = -1;
                                                    win.selName = "";
                                                }
                                            }
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text { text: "Process"; color: Theme.dim; font.pixelSize: 10; Layout.fillWidth: true }
                                    Text { text: "CPU"; color: Theme.dim; font.pixelSize: 10; Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight }
                                    Text { text: "Memory"; color: Theme.dim; font.pixelSize: 10; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                                }
                                Text {
                                    visible: win.bucketRows(win.appsKey).length === 0
                                    text: MonitorData.ready ? "No processes" : "Loading\u2026"
                                    color: Theme.dim
                                    font.pixelSize: 11
                                }
                                Repeater {
                                    model: win.bucketRows(win.appsKey)
                                    delegate: AppRow {
                                        required property var modelData
                                        entry: modelData
                                        selected: modelData.pid === win.selPid
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    spacing: 8
                                    Text {
                                        text: win.appsMsg.length ? win.appsMsg
                                            : (win.selPid >= 0 ? win.selName + "  (PID " + win.selPid + ")" : "Select a process")
                                        color: win.appsMsg.length ? Theme.accent : Theme.dim
                                        font.pixelSize: 10
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    ActionButton { label: "Launch"; onClicked: win.launchSelected() }
                                    ActionButton { label: "Kill"; onClicked: win.askKill(false) }
                                    ActionButton { label: "Force kill"; onClicked: win.askKill(true) }
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: win.confirmOpen
                            color: Qt.rgba(0, 0, 0, 0.45)
                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(360, parent.width - 40)
                                height: confirmCol.implicitHeight + 28
                                radius: 12
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.alpha(Theme.err, 0.6)
                                ColumnLayout {
                                    id: confirmCol
                                    anchors.centerIn: parent
                                    width: parent.width - 28
                                    spacing: 10
                                    Text {
                                        Layout.fillWidth: true
                                        text: (win.confirmForce ? "Force kill " : "Kill ") + win.selName + " (PID " + win.selPid + ")?"
                                        color: Theme.foreground
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "This will terminate the process. Unsaved work in it will be lost."
                                        color: Theme.dim
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Item { Layout.fillWidth: true }
                                        ActionButton { label: "Cancel"; onClicked: win.confirmOpen = false }
                                        ActionButton { label: "OK"; onClicked: win.confirmKill() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
