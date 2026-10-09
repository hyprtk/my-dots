// Right-click context menu for the bar.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"
import "../data"
import "../state"

PanelWindow {
    id: menu

    // Open on the clicked monitor (registered by the bar), else the focused one.
    property var targetScreen: null
    screen: Screens.byName(BarAnchors.barMenuScreen) || targetScreen

    anchors.top: BarConfig.barPosition === "top"
    anchors.bottom: BarConfig.barPosition === "bottom"
    anchors.left: true
    margins.top: BarConfig.barPosition === "top" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    // barMenuX is the cursor x relative to the bar window; the menu anchors to
    // the screen, so add the bar's left inset to line the menu edge up under the
    // cursor, then clamp it so it never runs off the right edge.
    readonly property int screenW: menu.screen ? menu.screen.width : 0
    readonly property real menuLeft:
        Math.max(4, Math.min(BarGeom.insets(menu.screenW).left + UiState.barMenuX,
                             Math.max(4, menu.screenW - menu.implicitWidth - 4)))
    margins.left: menu.menuLeft
    implicitWidth: 224
    implicitHeight: col.implicitHeight + 16
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    visible: UiState.barMenuOpen

    readonly property var entries: [
        { glyph: "\uf013", label: "Settings", act: "settings" },
        { glyph: "\uf021", label: "Reload", act: "reload" },
        { glyph: "\uf05a", label: "About hyprtk-bar-qt", act: "about" }
    ]

    // Persist the live widget layout before reloading, so a reload restores the
    // current arrangement. Save each widget's ACTUAL on-screen rect (from
    // WidgetMove), not the computed layout — the layout can lag a just-dropped
    // (or still-held) move, whereas the rects are what the user sees.
    readonly property string saveBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/widgets_layout.py").toString().replace("file://", "")
    function currentRects() {
        const out = ({});
        const r = WidgetMove.rects || ({});
        for (const id in r)
            out[id] = { x: Math.round(r[id].x), y: Math.round(r[id].y) };
        return out;
    }
    Process {
        id: saveProc
        onExited: (code, status) => Quickshell.reload(true)
    }

    function dispatch(action) {
        UiState.barMenuOpen = false;
        switch (action) {
        case "settings":
            UiState.settingsOpen = true;
            break;
        case "reload":
            saveProc.command = ["python3", menu.saveBackend, "save",
                "--layout", JSON.stringify(menu.currentRects())];
            saveProc.running = true;
            break;
        case "about":
            UiState.aboutOpen = true;
            break;
        }
    }

    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: menu.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        reveal = visible ? 1 : 0;
        if (visible)
            targetScreen = Screens.focused();
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.opacity)
        border.color: Theme.accent
        border.width: BarConfig.borderWidth
        SequentialAnimation on border.color {
            running: Chrome.animated
            loops: Animation.Infinite
            ColorAnimation { to: Theme.accent2; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
            ColorAnimation { to: Theme.accent; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
        }
        opacity: menu.reveal
        transform: Translate { y: (1 - menu.reveal) * -8 }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Repeater {
                model: menu.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 6
                    color: hover.hovered ? Theme.alpha(Theme.accent2, 0.18) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10
                        Text {
                            text: row.modelData.glyph
                            color: Theme.accent
                            font.pixelSize: 13
                        }
                        Text {
                            text: row.modelData.label
                            color: Theme.foreground
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                    }

                    HoverHandler { id: hover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menu.dispatch(row.modelData.act)
                    }
                }
            }
        }
    }
}
