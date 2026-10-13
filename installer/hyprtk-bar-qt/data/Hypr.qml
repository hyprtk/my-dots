// Hyprland dispatch helper: builds the right syntax for the running Hyprland.
//
// Hyprland >= 0.55 (Lua config) rejects the legacy `dispatch workspace 2` form
// and expects Lua expressions (`hl.dsp.focus({ workspace = 2 })`); older
// versions use the legacy form. The version is probed once via hyprctl.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Assume modern until the probe lands; corrected from `hyprctl version`.
    property bool lua: true
    property bool probed: false

    Process {
        running: true
        command: ["hyprctl", "version", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text);
                    const parts = String(v.version || v.tag || "0").replace(/^v/, "").split(".");
                    const maj = parseInt(parts[0]) || 0;
                    const min = parseInt(parts[1]) || 0;
                    root.lua = (maj > 0) || (min >= 55);
                } catch (e) {}
                root.probed = true;
            }
        }
    }

    // Quickshell's HyprlandToplevel.address is hex WITHOUT the `0x` prefix
    // (e.g. "561bd4a5a200"), but the Hyprland dispatchers expect it WITH the
    // prefix. Normalise so a bare address never reaches `address:...` (which
    // Hyprland rejects with "window not found").
    function _addr(addr) {
        const a = String(addr || "");
        return (a.length > 0 && a.indexOf("0x") !== 0) ? ("0x" + a) : a;
    }
    function workspace(id) {
        return root.lua ? ("hl.dsp.focus({ workspace = " + id + " })") : ("workspace " + id);
    }
    function focusWindow(addr) {
        const a = root._addr(addr);
        return root.lua ? ('hl.dsp.focus({ window = "address:' + a + '" })') : ("focuswindow address:" + a);
    }
    function closeWindow(addr) {
        const a = root._addr(addr);
        return root.lua ? ('hl.dsp.window.close({ window = "address:' + a + '" })') : ("closewindow address:" + a);
    }
    function moveWindowTo(ws, addr) {
        const a = root._addr(addr);
        return root.lua
            ? ('hl.dsp.window.move({ workspace = "' + ws + '", window = "address:' + a + '" })')
            : ("movetoworkspace " + ws + ",address:" + a);
    }
}
