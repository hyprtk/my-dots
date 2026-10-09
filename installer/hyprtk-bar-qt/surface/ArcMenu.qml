// Arc menu — a corner FAB whose items fan out along an arc (MaterialArcMenu
// concept, merged from the old hyprtk-arc-menu). Position/geometry/colours/
// animation/items come from the `arcmenu` config block.
//
// The corner FAB is shown whenever `arcmenu.enabled` is on; left-click it to
// fan the items out, left-click again to tuck them away, middle-click to
// disable. Also toggleable by Super+Ctrl+M, the bar button, or:
//   qs ipc call arcmenu toggle
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"
import "../state"
import "../data"

PanelWindow {
    id: arc

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // The surface is shown whenever the arc menu is enabled, so the corner FAB
    // is always reachable (like the GTK bar's overlay). While the items are
    // tucked away the surface is input/render-masked down to just the FAB, so
    // the empty corner never swallows clicks.
    visible: BarConfig.arcmenu.enabled !== false
    focusable: UiState.arcMenuOpen

    // Open on the focused monitor (resolved at start-up; single-monitor here).
    property var targetScreen: Screens.focused()
        || ((Quickshell.screens && Quickshell.screens.length) ? Quickshell.screens[0] : null)
    screen: targetScreen

    // Input + render region: the FAB when collapsed, the full surface when fanned.
    Region { id: fabMask; item: fab }
    Region { id: fullMask; x: 0; y: 0; width: arc.width; height: arc.height }
    mask: UiState.arcMenuOpen ? fullMask : fabMask

    onVisibleChanged: {
        if (!visible)
            UiState.arcMenuOpen = false;
    }

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/barsettings.py").toString().replace("file://", "")
    // Middle-clicking the FAB disables the arc menu (persisted), matching the
    // GTK bar; re-enable it from Settings → Arc Menu.
    Process {
        id: disableProc
        command: ["python3", arc.backend, "set", "--json", "{\"arcmenu\":{\"enabled\":false}}"]
    }

    readonly property var cfg: BarConfig.arcmenu
    readonly property string position: cfg.position || Config.arcMenuPosition
    readonly property var items: (cfg.items && cfg.items.length) ? cfg.items : Config.arcMenuItems
    readonly property bool usePywal: cfg.use_pywal !== false
    readonly property color fabColor: arc.usePywal ? Theme.accent : (cfg.fab_color || Theme.accent)
    readonly property color itemColor: arc.usePywal ? Theme.accent2 : (cfg.item_color || Theme.accent2)
    readonly property bool animOn: Config.uiAnimations && (BarConfig.animations.mode || "high") !== "off"
    readonly property int animMs: arc.animOn ? (cfg.animation_time || 300) : 0

    // Per-position fan (angles in degrees, screen y grows downward).
    readonly property var pos: ({
        "top-left":      { h: 0,   v: 0, start: 0,   end: 90  },
        "top-right":     { h: 1,   v: 0, start: 90,  end: 180 },
        "bottom-left":   { h: 0,   v: 1, start: 270, end: 360 },
        "bottom-right":  { h: 1,   v: 1, start: 180, end: 270 },
        "top-center":    { h: 0.5, v: 0, start: 0,   end: 180 },
        "bottom-center": { h: 0.5, v: 1, start: 180, end: 360 }
    }[arc.position] || { h: 1, v: 0, start: 90, end: 180 })

    readonly property bool centered: pos.h === 0.5
    readonly property int size: (cfg.radius || 92) * 2 + (cfg.item_size || 48) + 40
    readonly property int fabSize: cfg.fab_size || 46
    readonly property int itemSize: cfg.item_size || 42
    readonly property int edge: cfg.margin || 8
    readonly property int radius: cfg.radius || 92
    readonly property string shape: cfg.shape || "circle"

    anchors.top: pos.v === 0
    anchors.bottom: pos.v === 1
    anchors.left: pos.h === 0 || centered
    anchors.right: pos.h === 1 || centered
    implicitWidth: centered ? 640 : size
    implicitHeight: size

    function fabX() {
        if (pos.h === 0)
            return edge;
        if (pos.h === 1)
            return width - edge - fabSize;
        return (width - fabSize) / 2;
    }
    function fabY() {
        if (pos.v === 0)
            return edge;
        if (pos.v === 1)
            return height - edge - fabSize;
        return (height - fabSize) / 2;
    }

    function run(item) {
        if (cfg.close_on_click !== false)
            UiState.arcMenuOpen = false;
        if (item.action === "settings") {
            UiState.settingsOpen = true;
            return;
        }
        if (item.action === "themer") {
            UiState.themerOpen = true;
            return;
        }
        if (item.action === "clipboard") {
            UiState.clipboardOpen = true;
            return;
        }
        if (item.command)
            Quickshell.execDetached(["sh", "-c", item.command]);
    }

    IpcHandler {
        target: "arcmenu"
        function toggle() { UiState.arcMenuOpen = !UiState.arcMenuOpen; }
        function open() { UiState.arcMenuOpen = true; }
        function close() { UiState.arcMenuOpen = false; }
    }

    // items, fanned
    Repeater {
        model: arc.items

        delegate: Rectangle {
            id: cell
            required property var modelData
            required property int index

            readonly property real n: Math.max(1, arc.items.length)
            readonly property real t: cell.n <= 1 ? 0.5 : cell.index / (cell.n - 1)
            readonly property real angDeg: arc.pos.start + (arc.pos.end - arc.pos.start) * cell.t
            readonly property real ang: cell.angDeg * Math.PI / 180

            width: arc.itemSize
            height: arc.itemSize
            radius: arc.shape === "square" ? 8 : arc.itemSize / 2
            readonly property real openX: arc.fabX() + arc.fabSize / 2 + arc.radius * Math.cos(cell.ang) - width / 2
            readonly property real openY: arc.fabY() + arc.fabSize / 2 + arc.radius * Math.sin(cell.ang) - height / 2
            readonly property real closedX: arc.fabX() + arc.fabSize / 2 - width / 2
            readonly property real closedY: arc.fabY() + arc.fabSize / 2 - height / 2
            x: UiState.arcMenuOpen ? cell.openX : cell.closedX
            y: UiState.arcMenuOpen ? cell.openY : cell.closedY
            opacity: UiState.arcMenuOpen ? 1 : 0
            color: arc.itemColor
            border.color: arc.fabColor
            border.width: 1

            Behavior on x { enabled: arc.animOn; NumberAnimation { duration: arc.animMs; easing.type: Easing.OutBack } }
            Behavior on y { enabled: arc.animOn; NumberAnimation { duration: arc.animMs; easing.type: Easing.OutBack } }
            Behavior on opacity { enabled: arc.animOn; NumberAnimation { duration: arc.animMs } }

            Text {
                anchors.centerIn: parent
                text: cell.modelData.glyph || "\u2022"
                color: "#000000"
                font.family: BarConfig.glyphFont
                font.pixelSize: (arc.cfg.glyph_size > 0) ? arc.cfg.glyph_size
                    : Math.round(16 * (arc.itemSize / 42))
            }

            MouseArea {
                anchors.fill: parent
                enabled: UiState.arcMenuOpen
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: arc.run(cell.modelData)
            }
        }
    }

    // the FAB
    Rectangle {
        id: fab
        x: arc.fabX()
        y: arc.fabY()
        width: arc.fabSize
        height: arc.fabSize
        radius: arc.shape === "square" ? 10 : width / 2
        color: arc.fabColor

        Text {
            anchors.centerIn: parent
            text: arc.cfg.fab_glyph || "\uf00a"
            color: "#000000"
            font.family: BarConfig.glyphFont
            font.pixelSize: Math.round(arc.fabSize * 0.4)
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton) {
                    UiState.arcMenuOpen = false;
                    disableProc.running = true;
                } else {
                    UiState.arcMenuOpen = !UiState.arcMenuOpen;
                }
            }
        }
    }
}
