// Tray-hover info: runs the shared trayinfo backend while the tray is enabled
// and formats its sample into multi-line tooltip text.
//
// The tray module asks networkLines()/bluetoothLines() for the hovered item;
// any missing backend data degrades to an empty list so the module can fall
// back to the item title.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string backend:
        Qt.resolvedUrl("../backend/hyprtk_bar_qt/trayinfo.py").toString().replace("file://", "")
    readonly property bool enabled: BarConfig.tray.enabled !== false

    property var network: ({})
    property var bluetooth: ({})
    property bool ready: false

    Process {
        id: proc
        running: root.enabled
        command: ["python3", "-u", root.backend, "--interval", "2"]
        stdout: SplitParser {
            onRead: line => {
                let o;
                try {
                    o = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (o.network)
                    root.network = o.network;
                if (o.bluetooth)
                    root.bluetooth = o.bluetooth;
                root.ready = true;
            }
        }
    }

    function networkLines() {
        const n = root.network;
        if (!n || n.available === false || !n.device)
            return ["Network", "No active connection"];
        const out = ["Network — " + (n.connection || n.device)];
        out.push("Device: " + n.device);
        if (n.ip4)
            out.push("IPv4: " + n.ip4);
        if (n.gateway)
            out.push("Gateway: " + n.gateway);
        out.push("↓ " + SysData.humanBytes(n.down_bps || 0)
                 + "   ↑ " + SysData.humanBytes(n.up_bps || 0));
        return out;
    }

    function bluetoothLines() {
        const b = root.bluetooth;
        if (!b || b.available === false)
            return ["Bluetooth", "Adapter not available"];
        const adapter = b.adapter || "adapter";
        if (!b.powered)
            return ["Bluetooth — " + adapter, "Disabled"];
        const out = ["Bluetooth — " + adapter];
        const devices = b.devices || [];
        if (devices.length === 0) {
            out.push("No connected devices");
            return out;
        }
        out.push("Connected (" + devices.length + "):");
        for (let i = 0; i < devices.length; i++)
            out.push("  • " + devices[i].name + "  (" + devices[i].mac + ")");
        return out;
    }
}
