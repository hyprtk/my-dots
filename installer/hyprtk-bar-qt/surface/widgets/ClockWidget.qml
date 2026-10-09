// Desktop clock widget: digital / text / dials (single face or 3 H/M/S rings).
// Optional clock theme files override the look; the widget's own config wins.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"

WidgetFrame {
    id: win

    property var block: ({})
    widgetId: "clock"

    readonly property string home: Quickshell.env("HOME") || ""

    // ── clock theme file (user dir), merged under the widget's own block ──
    property var themeCfg: ({})
    FileView {
        id: themeFile
        path: win.block.theme
            ? win.home + "/.config/hyprtk-bar-qt/widget-themes/clock/" + String(win.block.theme).replace(/[^A-Za-z0-9_-]/g, "") + ".json"
            : ""
        printErrors: false
        onLoaded: {
            try { win.themeCfg = JSON.parse(themeFile.text()) || ({}); }
            catch (e) { win.themeCfg = ({}); }
        }
    }
    // widget block wins over the theme file; fallback last.
    function tv(key, fallback) {
        if (win.block[key] !== undefined)
            return win.block[key];
        if (win.themeCfg && win.themeCfg[key] !== undefined)
            return win.themeCfg[key];
        return fallback;
    }

    position: tv("position", "top-left")
    marginX: tv("margin_x", 40)
    marginY: tv("margin_y", 40)
    layer: tv("layer", "bottom")
    widgetWidth: tv("width", 220)
    widgetHeight: tv("height", 0)
    widgetOpacity: tv("opacity", 0.75)
    radius: tv("radius", 16)
    padding: tv("padding", 18)
    scale: tv("scale", 1.0)
    backgroundOverride: tv("background", "") || "transparent"
    foregroundOverride: tv("foreground", "") || "transparent"
    accentOverride: tv("accent", "") || "transparent"

    readonly property string style: tv("style", "digital")
    readonly property bool showSeconds: tv("show_seconds", false) === true
    readonly property int dialCount: Math.max(1, tv("dial_count", 1))
    readonly property int ringThickness: Math.max(2, tv("ring_thickness", 6))
    readonly property string fontFamily: tv("font", "") || Theme.fontFamily

    property SystemClock clock: SystemClock { precision: win.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }

    function qtFormat(fmt) {
        return (fmt || "%H:%M").replace(/%[HIpMSAadyBbm]/g, m => {
            switch (m) {
            case "%H": return "HH";
            case "%I": return "hh";
            case "%p": return "AP";
            case "%M": return "mm";
            case "%S": return "ss";
            case "%A": return "dddd";
            case "%a": return "ddd";
            case "%d": return "dd";
            case "%B": return "MMMM";
            case "%b": return "MMM";
            case "%m": return "MM";
            case "%Y": return "yyyy";
            case "%y": return "yy";
            }
            return m;
        });
    }
    function spell(h, m) {
        const hours = ["twelve", "one", "two", "three", "four", "five", "six", "seven",
            "eight", "nine", "ten", "eleven"];
        const tens = ["", "ten", "twenty", "thirty", "forty", "fifty"];
        const ones = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"];
        let mm = m < 10 ? "oh " + ones[m] : (m % 10 === 0 ? tens[m / 10] : tens[Math.floor(m / 10)] + " " + ones[m % 10]);
        if (m === 0)
            return hours[h % 12] + " o'clock";
        if (m === 15)
            return "quarter past " + hours[h % 12];
        if (m === 30)
            return "half past " + hours[h % 12];
        if (m === 45)
            return "quarter to " + hours[(h + 1) % 12];
        return hours[h % 12] + " " + mm;
    }

    readonly property var now: win.clock.date

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Math.round(4 * win.effScale)

        Canvas {
            id: dial
            visible: win.style === "dials"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.max(80, win.widgetWidth - 2 * win.padding)
            Layout.preferredHeight: Layout.preferredWidth
            onWidthChanged: requestPaint()
            Connections {
                target: win.clock
                function onDateChanged() { dial.requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const cx = width / 2, cy = height / 2;
                const R = Math.min(width, height) / 2 - 3;
                const d = win.clock.date;
                const sec = d.getSeconds(), min = d.getMinutes(), hr = d.getHours() % 12;

                if (win.dialCount >= 3) {
                    // Three concentric progress rings: hours, minutes, seconds.
                    const tw = win.ringThickness;
                    const gap = tw + 3;
                    function ring(radius, frac, color) {
                        ctx.lineWidth = tw;
                        ctx.strokeStyle = Theme.alpha(Theme.dim, 0.30);
                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                        ctx.stroke();
                        if (frac > 0) {
                            ctx.strokeStyle = color;
                            ctx.beginPath();
                            ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
                            ctx.stroke();
                        }
                    }
                    ring(R, (hr + min / 60) / 12, win.widgetAccent);
                    ring(R - gap, (min + sec / 60) / 60, win.widgetAccent);
                    if (win.showSeconds)
                        ring(R - gap * 2, sec / 60, win.widgetForeground);
                    return;
                }

                ctx.strokeStyle = win.widgetAccent;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.arc(cx, cy, R, 0, Math.PI * 2);
                ctx.stroke();
                // ticks
                for (let i = 0; i < 12; i++) {
                    const a = i * Math.PI / 6;
                    const inner = (i % 3 === 0) ? R - 9 : R - 5;
                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner);
                    ctx.lineTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R);
                    ctx.stroke();
                }
                function hand(angle, len, w, color) {
                    ctx.beginPath();
                    ctx.lineWidth = w;
                    ctx.strokeStyle = color;
                    ctx.moveTo(cx, cy);
                    ctx.lineTo(cx + Math.cos(angle) * len, cy + Math.sin(angle) * len);
                    ctx.stroke();
                }
                hand((hr + min / 60) * Math.PI / 6 - Math.PI / 2, R * 0.5, 3, win.widgetForeground);
                hand((min + sec / 60) * Math.PI / 30 - Math.PI / 2, R * 0.72, 2, win.widgetForeground);
                if (win.showSeconds)
                    hand(sec * Math.PI / 30 - Math.PI / 2, R * 0.82, 1, win.widgetAccent);
            }
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: win.style !== "dials"
            text: win.style === "text"
                ? win.spell(win.now.getHours(), win.now.getMinutes())
                : Qt.formatDateTime(win.now, win.qtFormat(win.tv("time_format", "%H:%M")))
            color: win.widgetForeground
            font.pixelSize: Math.round((win.style === "text" ? 22 : 42) * win.effScale)
            font.bold: win.style !== "text"
            font.family: win.fontFamily
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: win.tv("show_date", true) !== false
            text: Qt.formatDateTime(win.now, win.qtFormat(win.tv("date_format", "%A, %d %B")))
            color: win.widgetAccent
            font.pixelSize: Math.round(13 * win.effScale)
            font.family: win.fontFamily
        }
    }
}
