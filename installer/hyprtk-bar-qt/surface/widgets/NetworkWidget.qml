// Desktop network widget: interface, IP, up/down rates + download graph.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../data"
import "../../components"

WidgetFrame {
    id: win
    property var block: ({})
    widgetId: "network"

    position: block.position || "bottom-left"
    marginX: block.margin_x !== undefined ? block.margin_x : 40
    marginY: block.margin_y !== undefined ? block.margin_y : 40
    layer: block.layer || "bottom"
    widgetWidth: block.width || 300
    widgetHeight: block.height || 0
    widgetOpacity: block.opacity !== undefined ? block.opacity : 0.75
    radius: block.radius || 16
    padding: block.padding || 18
    scale: block.scale || 1.0
    backgroundOverride: block.background || "transparent"
    foregroundOverride: block.foreground || "transparent"
    accentOverride: block.accent || "transparent"

    readonly property bool showIp: block.show_ip !== false
    readonly property bool showRates: block.show_rates !== false
    readonly property bool showGraph: block.show_graph !== true ? block.show_graph !== false : true

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Math.round(4 * win.effScale)

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: WidgetData.net.glyph || "\uf1eb"; color: win.widgetAccent; font.family: BarConfig.glyphFont; font.pixelSize: Math.round(14 * win.effScale) }
            Text {
                text: WidgetData.ready ? (WidgetData.net.iface || "\u2014") : "\u2014"
                color: win.widgetForeground
                font.bold: true
                font.pixelSize: Math.round(14 * win.effScale)
                Layout.fillWidth: true
            }
        }
        Text {
            Layout.fillWidth: true
            visible: win.showIp
            text: WidgetData.ready ? (WidgetData.net.ip || "no address") : "no address"
            color: win.widgetForeground
            opacity: 0.85
            font.pixelSize: Math.round(12 * win.effScale)
        }
        Text {
            Layout.fillWidth: true
            visible: win.showRates
            text: WidgetData.ready
                ? "\uf019  " + MonitorData.fmtRate(WidgetData.net.down_bps || 0)
                    + "    \uf093  " + MonitorData.fmtRate(WidgetData.net.up_bps || 0)
                : "\uf019  --    \uf093  --"
            color: win.widgetAccent
            font.pixelSize: Math.round(12 * win.effScale)
        }
        Sparkline {
            visible: win.showGraph
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(44 * win.effScale)
            values: WidgetData.netDownHist
            color: win.widgetAccent
            scale: 0
        }
    }
}
