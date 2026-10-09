// Screen helpers for multi-monitor placement: map a connector name (registered
// by a bar module) to a ShellScreen, and resolve the focused monitor so centred
// dialogs open on the monitor the user is working on.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // A ShellScreen by Wayland output name (== Hyprland connector name), or null.
    function byName(name) {
        if (!name)
            return null;
        const all = Quickshell.screens || [];
        return all.find(s => s.name === name) || null;
    }

    // The focused monitor's ShellScreen; falls back to the first screen.
    function focused() {
        let name = "";
        try {
            name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        } catch (e) {
            name = "";
        }
        return root.byName(name) || ((Quickshell.screens && Quickshell.screens.length) ? Quickshell.screens[0] : null);
    }
}
