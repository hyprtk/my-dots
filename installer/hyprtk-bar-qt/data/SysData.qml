// Shared system telemetry: runs the Python backend once and exposes the latest
// sample plus rolling histories to every module that wants them.
//
// Keeping one Process means CPU/mem/net are sampled once, not once per widget.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/sysmon.py").toString().replace("file://", "")
    readonly property int histLen: 40

    // The Qt bar's own `sysmon` block (fallback to sane defaults).
    readonly property int intervalS: BarConfig.sysmon.interval || 1
    readonly property string diskPath: BarConfig.sysmon.disk_path || "/"

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property real rx: 0
    property real tx: 0
    property real diskUsed: 0
    property real diskTotal: 0

    property var cpuHist: []
    property var memHist: []
    property var diskHist: []
    property var rxHist: []
    property var txHist: []

    Process {
        id: proc
        running: true
        command: ["python3", "-u", root.backend, "--interval", String(root.intervalS), "--disk-path", root.diskPath]
        stdout: SplitParser {
            onRead: line => {
                let o;
                try {
                    o = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.cpu = o.cpu;
                root.mem = o.mem;
                root.disk = o.disk !== undefined ? o.disk : 0;
                root.rx = o.rx;
                root.tx = o.tx;
                root.diskUsed = o.disk_used !== undefined ? o.disk_used : 0;
                root.diskTotal = o.disk_total !== undefined ? o.disk_total : 0;
                root.cpuHist = root.cpuHist.concat([o.cpu]).slice(-root.histLen);
                root.memHist = root.memHist.concat([o.mem]).slice(-root.histLen);
                root.diskHist = root.diskHist.concat([root.disk]).slice(-root.histLen);
                root.rxHist = root.rxHist.concat([o.rx]).slice(-root.histLen);
                root.txHist = root.txHist.concat([o.tx]).slice(-root.histLen);
            }
        }
    }

    function humanBytes(b) {
        const units = ["B/s", "KiB/s", "MiB/s", "GiB/s"];
        let v = b, i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }
}
