// About box (bar right-click menu → About) — a centred layer-shell panel.
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
    id: about

    visible: UiState.aboutOpen
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 440
    implicitHeight: 320

    // Open on the focused monitor (captured when shown).
    property var targetScreen: null
    screen: targetScreen

    property real reveal: 0
    Behavior on reveal { NumberAnimation { duration: Config.animationDuration; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        reveal = visible ? 1 : 0;
        if (visible)
            targetScreen = Screens.focused();
    }

    // ── versions ───────────────────────────────────────────────────────
    readonly property string backendRoot:
        Qt.resolvedUrl("../backend/").toString().replace("file://", "")
    property string barVersion: ""
    property string qtVersion: ""
    property string qsVersion: ""

    Process {
        running: about.visible
        command: ["python3", "-c",
            "import sys; sys.path.insert(0, sys.argv[1]); import hyprtk_bar_qt; print(hyprtk_bar_qt.__version__)",
            about.backendRoot]
        stdout: SplitParser { onRead: line => about.barVersion = line.trim() }
    }
    Process {
        running: about.visible
        command: ["bash", "-lc",
            "qmake6 -query QT_VERSION 2>/dev/null || qmake -query QT_VERSION 2>/dev/null || qtpaths6 --qt-version 2>/dev/null"]
        stdout: SplitParser { onRead: line => about.qtVersion = line.trim() }
    }
    Process {
        running: about.visible
        command: ["bash", "-lc",
            "qs --version 2>/dev/null | sed -n 's/^Quickshell \\([0-9][0-9.]*\\).*/\\1/p'"]
        stdout: SplitParser { onRead: line => about.qsVersion = line.trim() }
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
        opacity: about.reveal
        transform: Translate { y: (1 - about.reveal) * -8 }
    }

    IpcHandler {
        target: "about"
        function toggle() { UiState.aboutOpen = !UiState.aboutOpen; }
        function open() { UiState.aboutOpen = true; }
        function close() { UiState.aboutOpen = false; }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 8
        opacity: about.reveal

        Text { text: "HYPRTK"; color: Theme.accent; font.bold: true; font.pixelSize: BarConfig.scaled(22); Layout.alignment: Qt.AlignHCenter }
        Text { text: "hyprtk-bar-qt"; color: Theme.foreground; font.pixelSize: BarConfig.scaled(13); Layout.alignment: Qt.AlignHCenter }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 8
            text: "A modern, pywal-themed taskbar for the Hyprland desktop — QML presentation with a toolkit-free Python backend."
            color: Theme.dim
            font.pixelSize: BarConfig.scaled(12)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            text: "hyprtk-bar-qt " + (about.barVersion || "\u2026")
                + "   \u00b7   Qt " + (about.qtVersion || "\u2026")
                + (about.qsVersion ? "   \u00b7   Quickshell " + about.qsVersion : "")
            color: Theme.foreground
            font.pixelSize: BarConfig.scaled(12)
        }
        Text { text: "github.com/hyprtk"; color: Theme.accent2; font.pixelSize: BarConfig.scaled(12); Layout.alignment: Qt.AlignHCenter }
        Item { Layout.fillHeight: true }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            TButton {
                text: "Close"
                onClicked: UiState.aboutOpen = false
            }
        }
    }
}
