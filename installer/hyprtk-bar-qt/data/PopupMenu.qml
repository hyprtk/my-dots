// Shared context-menu state.
//
// A single PopupWindow (components/BarMenuPopup.qml, declared in Bar.qml) draws
// the menu: Quickshell popups do not map inside a Repeater delegate, so modules
// just register the target item + a list of {label, action} entries here.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var target: null
    property var items: []
    property bool show: false

    function open(item, list) {
        root.target = item;
        root.items = list || [];
        root.show = true;
    }
    function close() {
        root.show = false;
        root.items = [];
    }
}
