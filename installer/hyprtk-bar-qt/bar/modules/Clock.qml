// Clock module: time from Quickshell's SystemClock. Format/font follow the
// `clock` / `font` config blocks (strftime formats converted to Qt).
import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../data"

Text {
    id: root
    visible: BarConfig.clock.enabled !== false

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    function qtFormat(fmt) {
        return String(fmt).replace(/%[HIpMSAadyBbm]/g, m => {
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

    readonly property string fmt: {
        const c = BarConfig.clock;
        return (typeof c.format === "string" && c.format.length > 0)
            ? root.qtFormat(c.format)
            : Config.clockFormat;
    }

    readonly property string dateFmt: {
        const c = BarConfig.clock;
        return (typeof c.date_format === "string" && c.date_format.length > 0)
            ? root.qtFormat(c.date_format) : "ddd dd MMM";
    }

    text: Qt.formatDateTime(clock.date, root.fmt)
    color: Theme.foreground
    font.bold: true
    font.pixelSize: BarConfig.fontSize(Theme.fontSize)
    font.family: BarConfig.fontFamily("Noto Sans")

    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: BarConfig.clock.calendar !== false
        onTapped: Cal.open(root)
    }
    HoverHandler {
        id: clkHover
        onHoveredChanged: clkHover.hovered
            ? Tooltips.showTip(root, Qt.formatDateTime(clock.date, root.dateFmt))
            : Tooltips.hideTip()
    }
}
