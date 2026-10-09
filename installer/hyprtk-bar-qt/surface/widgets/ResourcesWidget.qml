// Desktop resources widget: CPU / RAM / swap bars + temp / load.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../data"
import "../../components"

WidgetFrame {
    id: win
    property var block: ({})
    widgetId: "resources"

    position: block.position || "top-left"
    marginX: block.margin_x !== undefined ? block.margin_x : 40
    marginY: block.margin_y !== undefined ? block.margin_y : 40
    layer: block.layer || "bottom"
    widgetWidth: block.width || 280
    widgetHeight: block.height || 0
    widgetOpacity: block.opacity !== undefined ? block.opacity : 0.75
    radius: block.radius || 16
    padding: block.padding || 18
    scale: block.scale || 1.0
    backgroundOverride: block.background || "transparent"
    foregroundOverride: block.foreground || "transparent"
    accentOverride: block.accent || "transparent"

    readonly property bool showCpu: block.show_cpu !== false
    readonly property bool showRam: block.show_ram !== false
    readonly property bool showSwap: block.show_swap !== false
    readonly property bool showTemp: block.show_temp !== false
    readonly property bool showLoad: block.show_load !== false

    function frac(p) { return Math.min(Math.max((p || 0) / 100, 0), 1); }
    function meta() {
        const parts = [];
        const c = WidgetData.cpu;
        if (win.showTemp && c.temp_c !== undefined && c.temp_c !== null)
            parts.push(Math.round(c.temp_c) + "\u00b0C");
        if (win.showLoad && c.load)
            parts.push("load " + c.load.slice(0, 3).map(v => v.toFixed(2)).join(" "));
        return parts.join("   ");
    }

    component Metric: ColumnLayout {
        id: m
        property string label: ""
        property string value: ""
        property real fraction: 0
        Layout.fillWidth: true
        spacing: Math.round(3 * win.effScale)
        RowLayout {
            Layout.fillWidth: true
            Text { text: m.label; color: win.widgetForeground; opacity: 0.9; font.pixelSize: Math.round(12 * win.effScale); Layout.fillWidth: true }
            Text { text: m.value; color: win.widgetAccent; font.bold: true; font.pixelSize: Math.round(13 * win.effScale) }
        }
        Rectangle {
            Layout.fillWidth: true
            height: Math.round(6 * win.effScale)
            radius: height / 2
            color: Qt.rgba(win.widgetForeground.r, win.widgetForeground.g, win.widgetForeground.b, 0.15)
            Rectangle {
                width: parent.width * m.fraction
                height: parent.height
                radius: parent.radius
                color: win.widgetAccent
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Math.round(7 * win.effScale)

        Metric {
            visible: win.showCpu
            label: "CPU"
            value: WidgetData.ready ? Math.round(WidgetData.cpu.overall || 0) + "%" : "--"
            fraction: win.frac(WidgetData.cpu.overall)
        }
        Sparkline {
            visible: win.showCpu
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(40 * win.effScale)
            values: WidgetData.cpuHist
            color: win.widgetAccent
            scale: 100
        }
        Metric {
            visible: win.showRam
            label: "RAM"
            value: WidgetData.ready
                ? (WidgetData.mem.used_gb || 0).toFixed(1) + " / " + Math.round(WidgetData.mem.total_gb || 0) + " GiB"
                : "--"
            fraction: win.frac(WidgetData.mem.used_pct)
        }
        Metric {
            visible: win.showSwap
            label: "Swap"
            value: WidgetData.ready
                ? (WidgetData.mem.swap_used_gb || 0).toFixed(1) + " / " + Math.round(WidgetData.mem.swap_total_gb || 0) + " GiB"
                : "--"
            fraction: win.frac(WidgetData.mem.swap_pct)
        }
        Text {
            Layout.fillWidth: true
            visible: win.showTemp || win.showLoad
            text: win.meta()
            color: win.widgetForeground
            opacity: 0.8
            font.pixelSize: Math.round(11 * win.effScale)
        }
    }
}
