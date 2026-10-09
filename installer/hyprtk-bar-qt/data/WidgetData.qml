// Telemetry for the sampled desktop widgets (resources / disk / network).
//
// Runs the shared monitor backend only while at least one sampled widget is
// enabled, over just the pages those widgets need.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/monitor.py").toString().replace("file://", "")
    readonly property int histLen: 60

    readonly property var wantedPages: {
        const pages = [];
        if (Widgets.active("resources"))
            pages.push("cpu", "memory");
        if (Widgets.active("disk"))
            pages.push("disks");
        if (Widgets.active("network"))
            pages.push("network");
        return pages;
    }
    readonly property bool needs: wantedPages.length > 0

    property var sample: ({})
    property bool ready: false

    property var cpuHist: []
    property var memHist: []
    property var diskReadHist: []
    property var diskWriteHist: []
    property var netDownHist: []
    property var netUpHist: []

    readonly property var cpu: root.sample.cpu || ({})
    readonly property var mem: root.sample.memory || ({})
    readonly property var disk: root.sample.disk || ({})
    readonly property var drives: root.sample.drives || []
    readonly property var net: root.sample.net || ({})

    Process {
        id: proc
        running: root.needs
        command: ["python3", "-u", root.backend,
                  "--interval", "1",
                  "--pages", "cpu,memory,disks,network"]
        stdout: SplitParser {
            onRead: line => {
                let o;
                try {
                    o = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._ingest(o);
            }
        }
    }

    function _push(arr, v) {
        return arr.concat([v]).slice(-root.histLen);
    }

    function _ingest(o) {
        root.sample = o;
        root.ready = true;
        if (o.cpu)
            root.cpuHist = root._push(root.cpuHist, o.cpu.overall || 0);
        if (o.memory)
            root.memHist = root._push(root.memHist, o.memory.used_pct || 0);
        if (o.disk) {
            root.diskReadHist = root._push(root.diskReadHist, o.disk.read_bps || 0);
            root.diskWriteHist = root._push(root.diskWriteHist, o.disk.write_bps || 0);
        }
        if (o.net) {
            root.netDownHist = root._push(root.netDownHist, o.net.down_bps || 0);
            root.netUpHist = root._push(root.netUpHist, o.net.up_bps || 0);
        }
    }
}
