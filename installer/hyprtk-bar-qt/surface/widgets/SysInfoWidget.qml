// Desktop system-info widget: host / OS / kernel / uptime / CPU / GPU /
// memory / disks.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../data"

WidgetFrame {
    id: win
    property var block: ({})
    widgetId: "sysinfo"

    readonly property string backend:
        Qt.resolvedUrl("../../backend/hyprtk_bar_qt/sysinfo.py").toString().replace("file://", "")

    position: block.position || "bottom-left"
    marginX: block.margin_x !== undefined ? block.margin_x : 40
    marginY: block.margin_y !== undefined ? block.margin_y : 40
    layer: block.layer || "bottom"
    // Size to the content so long CPU/GPU model names are not clipped (the GTK
    // bar sizes its widget window to the natural content width).
    widgetWidth: Math.max(block.width || 320, Math.round(rowsCol.implicitWidth) + 2 * win.padding)
    widgetHeight: block.height || 0
    widgetOpacity: block.opacity !== undefined ? block.opacity : 0.75
    radius: block.radius || 16
    padding: block.padding || 18
    scale: block.scale || 1.0
    backgroundOverride: block.background || "transparent"
    foregroundOverride: block.foreground || "transparent"
    accentOverride: block.accent || "transparent"

    property var info: ({})

    Process {
        id: proc
        command: ["python3", win.backend]
        stdout: SplitParser {
            onRead: line => {
                try { win.info = JSON.parse(line); } catch (e) { win.info = ({}); }
            }
        }
    }
    Timer {
        running: win.visible
        interval: Math.max(2, block.refresh_seconds || 10) * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    function rows() {
        const i = win.info;
        const out = [];
        const add = (flag, glyph, label, value) => {
            if (block[flag] !== false && value)
                out.push({ glyph: glyph, label: label, value: String(value) });
        };
        add("show_host", "\uf109", "Host", i.host);
        add("show_os", "\uf17c", "OS", i.os);
        add("show_kernel", "\uf17c", "Kernel", i.kernel);
        add("show_uptime", "\uf017", "Uptime", i.uptime);
        add("show_cpu", "\uf2db", "CPU", i.cpu);
        add("show_gpu", "\uf108", "GPU", i.gpu);
        add("show_memory", "\uf1c0", "Memory", i.mem_total ? Number(i.mem_total).toFixed(1) + " GiB" : "");
        if (block.show_disks !== false && i.disk_count)
            out.push({ glyph: "\uf0a0", label: "Disks", value: i.disk_count + " \u00d7 " + i.disk_total });
        return out;
    }

    ColumnLayout {
        id: rowsCol
        Layout.fillWidth: true
        spacing: Math.round(4 * win.effScale)
        Repeater {
            model: win.rows()
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Text { text: row.modelData.glyph; color: win.widgetAccent; font.family: BarConfig.glyphFont; font.pixelSize: Math.round(16 * win.effScale) }
                Text {
                    text: row.modelData.label
                    color: win.widgetForeground
                    opacity: 0.7
                    font.pixelSize: Math.round(12 * win.effScale)
                    Layout.preferredWidth: Math.round(72 * win.effScale)
                }
                Text {
                    text: row.modelData.value
                    color: win.widgetForeground
                    font.pixelSize: Math.round(12 * win.effScale)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }
}
