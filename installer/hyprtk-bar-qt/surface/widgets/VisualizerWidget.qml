// Desktop audio visualizer (cava): bars / wave / mirror / dots / glow.
// source (cava/synthetic), sensitivity, smoothing, orientation and peak dots
// are applied here; the raw frames come from backend/.../visualizer.py.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"

WidgetFrame {
    id: win
    property var block: ({})
    widgetId: "visualizer"

    readonly property string backend:
        Qt.resolvedUrl("../../backend/hyprtk_bar_qt/visualizer.py").toString().replace("file://", "")
    readonly property int bars: Math.max(8, block.bars || 48)

    readonly property real sensitivity: {
        const s = block.sensitivity;
        return (typeof s === "number" && s > 0) ? s : 1.0;
    }
    readonly property real smoothing: {
        const s = block.smoothing;
        return (typeof s === "number" && s >= 0) ? Math.min(0.95, s) : 0.0;
    }
    readonly property bool peakDots: block.peak_dots === true
    readonly property bool flip: block.orientation === "down"
    readonly property string source: block.source || "auto"

    position: block.position || "bottom-center"
    marginX: block.margin_x !== undefined ? block.margin_x : 40
    marginY: block.margin_y !== undefined ? block.margin_y : 40
    layer: block.layer || "bottom"
    widgetWidth: block.width || 420
    widgetHeight: block.height || 120
    widgetOpacity: block.opacity !== undefined ? block.opacity : 0.6
    radius: block.radius || 16
    padding: block.padding || 12
    scale: block.scale || 1.0
    backgroundOverride: block.background || "transparent"
    foregroundOverride: block.foreground || "transparent"
    accentOverride: block.accent || "transparent"

    property var levels: []     // displayed (smoothed + sensitivity)
    property var peaks: []
    readonly property string style: block.style || "bars"

    // Apply sensitivity + temporal smoothing and track peaks.
    function applyFrame(vals) {
        const n = vals.length;
        const out = [];
        const pk = [];
        for (let i = 0; i < n; i++) {
            const v = Math.min(1, Math.max(0, vals[i]) * win.sensitivity);
            const prev = win.levels[i] !== undefined ? win.levels[i] : 0;
            out.push(prev * win.smoothing + v * (1 - win.smoothing));
            const prevP = win.peaks[i] !== undefined ? win.peaks[i] : 0;
            pk.push(v >= prevP ? v : Math.max(0, prevP - 0.01));
        }
        win.levels = out;
        win.peaks = pk;
    }

    Process {
        id: proc
        command: ["python3", "-u", win.backend, "--bars", String(win.bars),
                  "--fps", String(block.fps || 60), "--binary", block.cava_binary || "cava",
                  "--source", win.source]
        stdout: SplitParser {
            onRead: line => {
                try { win.applyFrame(JSON.parse(line).levels || []); } catch (e) {}
            }
        }
    }
    Timer {
        running: win.visible
        interval: 500
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    function hexToRgb(h) {
        const s = String(h).replace("#", "");
        if (s.length < 6)
            return [200, 132, 252];
        return [parseInt(s.substr(0, 2), 16), parseInt(s.substr(2, 2), 16), parseInt(s.substr(4, 2), 16)];
    }
    function mix(a, b, t) {
        const A = win.hexToRgb(a), B = win.hexToRgb(b);
        return "rgb(" + Math.round(A[0] + (B[0] - A[0]) * t) + ","
            + Math.round(A[1] + (B[1] - A[1]) * t) + ","
            + Math.round(A[2] + (B[2] - A[2]) * t) + ")";
    }
    function colorFor(i, n, color) {
        const mode = block.color_mode || "pywal";
        if (mode === "custom" && block.color)
            return block.color;
        if (mode === "gradient" && block.gradient_from && block.gradient_to)
            return win.mix(block.gradient_from, block.gradient_to, n > 1 ? i / (n - 1) : 0);
        if (mode === "accent")
            return win.widgetAccent;
        // pywal (default)
        return Theme.walColor(5, win.widgetAccent);
    }

    Canvas {
        id: canvas
        Layout.fillWidth: true
        Layout.fillHeight: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: win
            function onLevelsChanged() { canvas.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const vals = win.levels;
            if (!vals || vals.length === 0 || width < 4)
                return;
            const n = vals.length;
            const slot = width / n;
            const bw = Math.max(1, slot * 0.7);
            const style = win.style;
            const glow = style === "glow";
            if (glow)
                ctx.shadowBlur = 10;
            function yFor(v) { return win.flip ? v * height : height - v * height; }

            if (style === "wave") {
                ctx.beginPath();
                for (let i = 0; i < n; i++) {
                    const x = i * slot + slot / 2;
                    const y = yFor(Math.min(1, vals[i]));
                    if (i === 0)
                        ctx.moveTo(x, y);
                    else
                        ctx.lineTo(x, y);
                }
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.strokeStyle = win.colorFor(0, 1, "wave");
                ctx.stroke();
                return;
            }

            for (let i = 0; i < n; i++) {
                const v = Math.max(0, Math.min(1, vals[i]));
                const color = win.colorFor(i, n, "bar");
                ctx.fillStyle = color;
                if (glow)
                    ctx.shadowColor = color;
                const x = i * slot + (slot - bw) / 2;
                if (style === "dots") {
                    const r = Math.max(1, bw / 2);
                    ctx.beginPath();
                    ctx.arc(x + r, yFor(v), r * (0.5 + 0.5 * v), 0, Math.PI * 2);
                    ctx.fill();
                } else if (style === "mirror") {
                    const h = v * height / 2;
                    ctx.fillRect(x, height / 2 - h, bw, h * 2);
                } else {
                    const h = v * height;
                    ctx.fillRect(x, win.flip ? 0 : height - h, bw, h);
                }
            }

            // peak dots
            if (win.peakDots && style !== "mirror") {
                for (let i = 0; i < n; i++) {
                    const p = win.peaks[i] || 0;
                    if (p <= 0.01)
                        continue;
                    ctx.fillStyle = win.colorFor(i, n, "peak");
                    const x = i * slot + slot / 2;
                    ctx.beginPath();
                    ctx.arc(x, yFor(p), 1.5, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }
    }
}
