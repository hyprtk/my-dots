// Desktop disk widget: per-drive usage bars + aggregate read/write rates.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../data"
import "../../components"

WidgetFrame {
    id: win
    property var block: ({})
    widgetId: "disk"

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

    readonly property bool showBar: block.show_bar !== false
    readonly property bool showRates: block.show_rates !== false
    readonly property int drivesMax: block.drives_max || 3

    function visibleDrives() {
        return (WidgetData.drives || []).slice(0, win.drivesMax);
    }
    function frac(d) {
        const denom = (d.used_b || 0) + (d.free_b || 0);
        return denom > 0 ? (d.used_b || 0) / denom : 0;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Math.round(8 * win.effScale)

        Repeater {
            model: win.visibleDrives()
            delegate: ColumnLayout {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                spacing: Math.round(3 * win.effScale)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: cell.modelData.glyph || ""; color: win.widgetAccent; font.family: BarConfig.glyphFont; font.pixelSize: Math.round(16 * win.effScale) }
                    Text {
                        text: cell.modelData.model || cell.modelData.name || ""
                        color: win.widgetForeground
                        font.bold: true
                        font.pixelSize: Math.round(12 * win.effScale)
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        text: cell.modelData.size_b > 0
                            ? MonitorData.fmtBytes(cell.modelData.used_b) + " / " + MonitorData.fmtBytes(cell.modelData.size_b)
                            : "\u2014"
                        color: win.widgetForeground
                        opacity: 0.85
                        font.pixelSize: Math.round(11 * win.effScale)
                    }
                }
                MeterBar {
                    visible: win.showBar && modelData.size_b > 0
                    height: Math.round(6 * win.effScale)
                    fraction: win.frac(cell.modelData)
                    trackColor: Qt.rgba(win.widgetForeground.r, win.widgetForeground.g, win.widgetForeground.b, 0.15)
                    fillColor: win.widgetAccent
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: win.showRates
            text: WidgetData.ready
                ? "\uf019  " + MonitorData.fmtRate(WidgetData.disk.read_bps || 0)
                    + "    \uf093  " + MonitorData.fmtRate(WidgetData.disk.write_bps || 0)
                : "\uf019  --    \uf093  --"
            color: win.widgetAccent
            font.pixelSize: Math.round(12 * win.effScale)
        }
    }
}
