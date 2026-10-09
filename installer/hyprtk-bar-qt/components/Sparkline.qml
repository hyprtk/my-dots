// Rolling line + gradient-area sparkline, drawn on a Canvas.
//
// Mirrors the GTK bar's single-series HistoryGraph: newest value at the right
// edge, history scrolling left, optional fixed scale (0 = autoscale).
import QtQuick

Canvas {
    id: root

    property var values: []
    property color color: "#7aa2f7"
    property real scale: 0        // 0 = autoscale to the max observed value
    property int maxPoints: 40
    property real inset: 2
    property real strokeWidth: 1.5

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onScaleChanged: requestPaint()
    onMaxPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const vals = root.values;
        if (vals.length < 2 || width < 4 || height < 4)
            return;

        const pad = root.inset;
        const xw = width - pad * 2;
        const yh = height - pad * 2;
        const slot = Math.max(1, root.maxPoints - 1);
        const sc = root.scale > 0 ? root.scale
                                  : Math.max(1e-6, Math.max.apply(null, vals));

        function x(i) { return pad + i * xw / slot; }
        function y(v) { return pad + (1 - Math.min(Math.max(v / sc, 0), 1)) * yh; }

        // gradient area
        ctx.beginPath();
        ctx.moveTo(x(0), y(vals[0]));
        for (let i = 1; i < vals.length; i++)
            ctx.lineTo(x(i), y(vals[i]));
        ctx.lineTo(x(vals.length - 1), height - pad);
        ctx.lineTo(x(0), height - pad);
        ctx.closePath();
        const g = ctx.createLinearGradient(0, 0, 0, height);
        g.addColorStop(0, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.32));
        g.addColorStop(1, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.02));
        ctx.fillStyle = g;
        ctx.fill();

        // line
        ctx.beginPath();
        ctx.moveTo(x(0), y(vals[0]));
        for (let i = 1; i < vals.length; i++)
            ctx.lineTo(x(i), y(vals[i]));
        ctx.lineWidth = root.strokeWidth;
        ctx.lineJoin = "round";
        ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.95);
        ctx.stroke();
    }
}
