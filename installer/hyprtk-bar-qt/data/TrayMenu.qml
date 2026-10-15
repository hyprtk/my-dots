// Shared tray context-menu state.
//
// The tray module hands us the SNI item's DBusMenu handle; a single themed
// PopupWindow (components/TrayMenuPopup.qml, declared in Bar.qml) renders it.
// Like the other popups it must live at a stable item — Quickshell popups do
// not map inside a Repeater delegate.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var target: null      // QQuickItem the menu anchors to
    property var handle: null      // QsMenuHandle (SNI item's DBusMenu)
    property bool show: false

    function open(item, h) {
        root.target = item;
        root.handle = h;
        root.show = true;
    }
    function close() {
        root.show = false;
    }
}
