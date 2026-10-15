// Shared bar-tooltip state.
//
// A single PopupWindow (components/BarTooltip.qml, declared in Bar.qml) renders
// the tooltip: Quickshell popups do not map when declared inside a Repeater
// delegate, so modules just register the hovered item + text here.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var target: null
    property var lines: []
    property bool show: false

    // Single-line convenience (every module except the tray uses this).
    readonly property string text: root.lines.join("\n")

    function showTip(item, t) {
        root.target = item;
        root.lines = (t === undefined || t === null || t === "") ? [] : [String(t)];
        root.show = true;
    }
    // Multi-line tooltip (the tray: network/bluetooth details).
    function showLines(item, ls) {
        root.target = item;
        root.lines = (ls && ls.length) ? ls : [];
        root.show = true;
    }
    function hideTip() {
        root.show = false;
    }
}
