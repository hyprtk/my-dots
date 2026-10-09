// CPU / memory / disk module: live percentage + a rolling sparkline each.
//
// Values come from the shared SysData singleton (Python backend), not from a
// per-widget process. Percentages colour at 70% (warn) / 90% (high).
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../state"
import "../../data"
import "../../components"

RowLayout {
    id: root
    spacing: 10
    visible: BarConfig.sysmon.enabled !== false

    readonly property int fs: BarConfig.fontSize(11)
    readonly property bool monitorEnabled: BarConfig.sysmon.monitor !== false

    // Our monitor (the bar window's screen), so the monitor dialog opens here.
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    // Register our window-relative position so the dialog lines up under us.
    function _register() { BarAnchors.setSysmon(mapToItem(null, 0, 0).x, width, root.screenName); }
    Component.onCompleted: _register()
    onXChanged: _register()
    onWidthChanged: _register()
    onScreenNameChanged: _register()

    function levelColor(pct) {
        return pct >= 90 ? Theme.err : (pct >= 70 ? Theme.warn : Theme.foreground);
    }

    component Metric: RowLayout {
        id: m
        property string glyph: ""
        property color glyphColor: Theme.dim
        property real pct: 0
        spacing: 4
        Text { text: m.glyph; color: m.glyphColor; font.family: BarConfig.glyphFont; font.pixelSize: BarConfig.iconSize(root.fs) }
        Text {
            text: Math.round(m.pct) + "%"
            color: root.levelColor(m.pct)
            font.pixelSize: root.fs
            Layout.preferredWidth: 30
        }
    }

    Metric { glyph: "\uf2db"; glyphColor: Theme.accent; pct: SysData.cpu * 100 }
    Metric { glyph: "\uefc5"; glyphColor: Theme.accent2; pct: SysData.mem * 100 }
    Metric { glyph: String.fromCodePoint(0xf02ca); glyphColor: Theme.dim; pct: SysData.disk * 100 }

    // Left-click opens the Mission Center-style system monitor dialog.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (root.monitorEnabled)
                UiState.sysMonitorOpen = true;
        }
    }
    HoverHandler {
        id: smHover
        cursorShape: root.monitorEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: smHover.hovered
            ? Tooltips.showTip(root, "CPU: " + Math.round(SysData.cpu * 100) + "%\nRAM: "
                + Math.round(SysData.mem * 100) + "% (" + SysData.diskUsed.toFixed(1) + "/" + SysData.diskTotal.toFixed(1) + " GB disk)")
            : Tooltips.hideTip()
    }
}
