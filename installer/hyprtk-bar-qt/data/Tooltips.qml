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
    property string text: ""
    property bool show: false

    function showTip(item, t) {
        root.target = item;
        root.text = t;
        root.show = true;
    }
    function hideTip() {
        root.show = false;
    }
}
