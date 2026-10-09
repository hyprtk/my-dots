// Package-update indicator: runs the hyprtk updates script periodically and
// shows the pending count, coloured by the script's JSON class. Click runs the
// installer. Mirrors the GTK bar: the script must live under a bar/repo-owned
// root (it runs on a timer), and its JSON `{text,class,tooltip}` is honoured.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../data"

Text {
    id: root

    property string label: "0"
    property string cssClass: "green"
    property string tip: ""

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string script: BarConfig.updates.script || (root.home + "/.local/share/hyprtk-bar-qt/scripts/updates.sh")
    readonly property string install: BarConfig.updates.install_command || (root.home + "/.local/share/hyprtk-bar-qt/scripts/installupdates.sh")
    readonly property int intervalS: BarConfig.updates.interval || 60

    // Only run scripts from bar/repo-owned roots (never an arbitrary path).
    readonly property bool scriptAllowed: {
        const roots = [
            root.home + "/.local/share/hyprtk-bar-qt",
            root.home + "/.local/bin",
            root.home + "/hyprtk/installer/scripts"
        ];
        const p = root.script;
        return roots.some(r => p === r || p.startsWith(r + "/"));
    }

    visible: BarConfig.updates.enabled !== false && root.scriptAllowed
    text: "\uf0ab " + root.label
    color: root.cssClass === "red" ? Theme.err : (root.cssClass === "yellow" ? Theme.warn : Theme.foreground)
    font.family: BarConfig.glyphFont
    font.pixelSize: BarConfig.fontSize(Theme.fontSize)

    Process {
        id: proc
        command: ["bash", root.script]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = (text || "").trim();
                try {
                    const d = JSON.parse(out);
                    root.label = String(d.text !== undefined ? d.text : "0");
                    root.cssClass = String(d.class || "green");
                    root.tip = String(d.tooltip || "");
                } catch (e) {
                    const m = out.match(/[0-9]+/);
                    const n = m ? parseInt(m[0]) : 0;
                    root.label = String(n);
                    root.cssClass = n >= 20 ? "red" : (n > 0 ? "yellow" : "green");
                    root.tip = root.label + " update(s)";
                }
            }
        }
    }

    Timer {
        interval: Math.max(30, root.intervalS) * 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    HoverHandler {
        id: updHover
        onHoveredChanged: (updHover.hovered && root.tip.length)
            ? Tooltips.showTip(root, root.tip)
            : Tooltips.hideTip()
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.install.length && root.install.startsWith(root.home + "/.local"))
                Quickshell.execDetached(["bash", root.install]);
        }
    }
}
