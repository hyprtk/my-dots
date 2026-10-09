// Keyboard-state module: Caps Lock / Num Lock indicators, fed by the Python
// kbleds backend (reads /sys/class/leds).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../data"

RowLayout {
    id: root
    spacing: 5
    readonly property int fs: BarConfig.fontSize(11)

    property bool caps: false
    property bool num: false

    readonly property string backend:
        Qt.resolvedUrl("../../backend/hyprtk_bar_qt/kbleds.py").toString().replace("file://", "")

    Process {
        id: proc
        running: true
        command: ["python3", "-u", root.backend, "--interval", "0.5"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const o = JSON.parse(line);
                    root.caps = o.caps;
                    root.num = o.num;
                } catch (e) {
                }
            }
        }
    }

    HoverHandler {
        id: kbHover
        onHoveredChanged: kbHover.hovered
            ? Tooltips.showTip(root, "Caps: " + (root.caps ? "on" : "off") + "  Num: " + (root.num ? "on" : "off"))
            : Tooltips.hideTip()
    }
    Text {
        text: "\uf023"
        color: root.caps ? Theme.accent : Theme.dim
        font.family: BarConfig.glyphFont
        font.pixelSize: BarConfig.iconSize(root.fs)
    }
    Text {
        text: "\uf11c"
        color: root.num ? Theme.accent : Theme.dim
        font.family: BarConfig.glyphFont
        font.pixelSize: BarConfig.iconSize(root.fs)
    }
}
