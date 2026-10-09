// Rich system-monitor telemetry for surface/SysMonitor.qml.
//
// Spawns the Python backend (backend/hyprtk_bar_qt/monitor.py) only while the
// dialog is open, parses its JSON lines, and exposes the latest sample plus
// rolling histories for the graphs. The heavy /proc, /sys, lsblk, nvidia-smi
// and hyprctl work stays in Python.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "."

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/monitor.py").toString().replace("file://", "")
    readonly property string actionBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/proc_action.py").toString().replace("file://", "")
    readonly property string dimmBackend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/dimm.py").toString().replace("file://", "")

    readonly property int histLen: Math.max(10, scfg.data_points || Config.sysmonDataPoints)

    // The Qt bar's own `sysmon` block (what this dialog and the Settings page edit),
    // falling back to the Qt bar's own config.
    readonly property var scfg: BarConfig.sysmon
    readonly property int intervalS: scfg.interval || Config.sysmonInterval
    readonly property var pageList: (scfg.pages && scfg.pages.length) ? scfg.pages : Config.sysmonPages
    readonly property string diskPath: scfg.disk_path || Config.sysmonDiskPath
    readonly property string netIface: scfg.network_iface || Config.sysmonNetworkIface

    // Set true by the dialog while it is visible; starts/stops the process.
    property bool active: false

    // The page currently on screen. Changing it restarts the backend so the
    // expensive process walk only runs while the Apps page is visible.
    property string activePage: "cpu"

    // Latest full sample object ({} until the first line arrives).
    property var sample: ({})
    property bool ready: false

    // The drive the disk graphs track ("" = auto: the root disk).
    property string selectedDrive: ""

    // DIMM slots (SMBIOS): loaded lazily from the cache, refreshed on demand.
    property var dimmSlots: []
    property bool dimmLoaded: false
    property string dimmStatus: ""

    property var cpuHist: []
    property var cpuTempHist: []
    property var memHist: []
    property var swapHist: []
    property var diskUsageHist: []
    property var diskReadHist: []
    property var diskWriteHist: []
    property var netDownHist: []
    property var netUpHist: []
    property var gpuUtilHist: []
    property var gpuVramHist: []

    // Convenience accessors (with safe defaults before the first sample).
    readonly property var cpu: root.sample.cpu || ({})
    readonly property var mem: root.sample.memory || ({})
    readonly property var disk: root.sample.disk || ({})
    readonly property var drives: root.sample.drives || []
    readonly property var net: root.sample.net || ({})
    readonly property var gpu: root.sample.gpu || null
    readonly property var gpuStatic: root.sample.gpu_static || null
    readonly property var apps: root.sample.apps || []
    readonly property int uid: (typeof root.sample.uid === "number") ? root.sample.uid : -1

    Process {
        id: proc
        running: root.active
        command: [
            "python3", "-u", root.backend,
            "--interval", String(root.intervalS),
            "--pages", (root.pageList || []).join(","),
            "--disk-path", root.diskPath,
            "--iface", root.netIface,
            "--active", root.activePage
        ]
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

    // DIMM slots: cached read is instant; --fetch may prompt via pkexec.
    Process {
        id: dimmProc
        stdout: SplitParser {
            onRead: line => {
                let o;
                try {
                    o = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.dimmSlots = o.slots || [];
                root.dimmLoaded = root.dimmSlots.length > 0;
                root.dimmStatus = root.dimmSlots.length ? "" : "DIMM info unavailable \u2014 click refresh";
            }
        }
    }

    function loadDimm(force) {
        if (dimmProc.running)
            return;
        root.dimmStatus = force ? "Reading DIMM slots\u2026" : "";
        dimmProc.command = ["python3", root.dimmBackend].concat(force ? ["--fetch"] : []);
        dimmProc.running = true;
    }

    function dimmPopulated() {
        return root.dimmSlots.filter(s => s.populated).length;
    }
    function dimmTotalGb() {
        return root.dimmSlots.reduce((a, s) => a + (s.size_gb || 0), 0);
    }

    onActiveChanged: {
        if (!root.active)
            return;
        root.sample = ({});
        root.ready = false;
        root.cpuHist = [];
        root.cpuTempHist = [];
        root.memHist = [];
        root.swapHist = [];
        root.diskUsageHist = [];
        root.diskReadHist = [];
        root.diskWriteHist = [];
        root.netDownHist = [];
        root.netUpHist = [];
        root.gpuUtilHist = [];
        root.gpuVramHist = [];
    }

    function _push(arr, v) {
        return arr.concat([v]).slice(-root.histLen);
    }

    function _ingest(o) {
        root.sample = o;
        root.ready = true;

        if (o.cpu) {
            root.cpuHist = root._push(root.cpuHist, o.cpu.overall);
            const t = (typeof o.cpu.temp_c === "number")
                ? o.cpu.temp_c
                : (root.cpuTempHist.length ? root.cpuTempHist[root.cpuTempHist.length - 1] : 0);
            root.cpuTempHist = root._push(root.cpuTempHist, t);
        }
        if (o.memory) {
            root.memHist = root._push(root.memHist, o.memory.used_pct);
            root.swapHist = root._push(root.swapHist, o.memory.swap_pct);
        }
        if (o.disk) {
            root.diskReadHist = root._push(root.diskReadHist, o.disk.read_bps);
            root.diskWriteHist = root._push(root.diskWriteHist, o.disk.write_bps);
            const target = root._resolveDrive(o.drives || []);
            root.diskUsageHist = root._push(root.diskUsageHist, root._drivePct(target));
        }
        if (o.net) {
            root.netDownHist = root._push(root.netDownHist, o.net.down_bps);
            root.netUpHist = root._push(root.netUpHist, o.net.up_bps);
        }
        if (o.gpu) {
            root.gpuUtilHist = root._push(root.gpuUtilHist, o.gpu.util_pct || 0);
            const vt = o.gpu.vram_total_gb, vu = o.gpu.vram_used_gb;
            root.gpuVramHist = root._push(
                root.gpuVramHist, (vt && vt > 0) ? 100 * (vu || 0) / vt : 0);
        }
    }

    // The drive the usage graph tracks: the explicit selection, else the root
    // disk, else the first mounted drive.
    function _resolveDrive(drives) {
        let target = drives.find(d => d.name === root.selectedDrive);
        if (target)
            return target;
        target = drives.find(d => d.is_root)
            || drives.find(d => d.used_b + d.free_b > 0)
            || (drives.length ? drives[0] : null);
        if (target)
            root.selectedDrive = target.name;
        return target;
    }

    function _drivePct(drive) {
        if (!drive)
            return 0;
        const denom = drive.used_b + drive.free_b;
        return denom > 0 ? 100 * drive.used_b / denom : 0;
    }

    // Per-device read/write rate for a drive name (0 when idle/unknown).
    function deviceRate(name) {
        const devs = root.disk.devices || [];
        const d = devs.find(x => x.name === name);
        return d ? { read: d.read_bps, write: d.write_bps } : { read: 0, write: 0 };
    }

    function selectedDriveInfo() {
        return (root.drives || []).find(d => d.name === root.selectedDrive) || null;
    }

    function fmtBytes(b) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let v = Math.max(0, b || 0), i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    function fmtRate(bps) {
        return root.fmtBytes(bps) + "/s";
    }

    function fmtUptime(seconds) {
        let s = Math.floor(seconds || 0);
        const d = Math.floor(s / 86400);
        s -= d * 86400;
        const h = Math.floor(s / 3600);
        s -= h * 3600;
        const m = Math.floor(s / 60);
        if (d)
            return d + "d " + h + "h " + m + "m";
        if (h)
            return h + "h " + m + "m";
        return m + "m";
    }
}
