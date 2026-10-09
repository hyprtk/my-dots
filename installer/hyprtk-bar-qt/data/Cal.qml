// Shared calendar-popup state (opened by the clock module).
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var target: null
    property bool show: false
    property date view: new Date()

    function open(item) {
        root.target = item;
        root.view = new Date();
        root.show = true;
    }
    function close() {
        root.show = false;
    }
    function prev() {
        root.view = new Date(root.view.getFullYear(), root.view.getMonth() - 1, 1);
    }
    function next() {
        root.view = new Date(root.view.getFullYear(), root.view.getMonth() + 1, 1);
    }
}
