// Desktop-widget configuration, read from the Qt bar's own config
// (`widgets` block in ~/.config/hyprtk-bar-qt/config.json).
//
// The Qt bar keeps its own widget layout, separate from the GTK bar's; editing
// lives on the Settings → Widgets page.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""

    property var cfg: ({})

    FileView {
        id: cfgFile
        path: root.home + "/.config/hyprtk-bar-qt/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: root._parse()
        onTextChanged: root._parse()
        onFileChanged: reload()
    }
    function _parse() {
        try {
            root.cfg = (JSON.parse(cfgFile.text()).widgets) || ({});
        } catch (e) {
            root.cfg = ({});
        }
    }

    readonly property bool masterEnabled: root.cfg.enabled === true
    readonly property bool transparent: root.cfg.transparent === true
    readonly property bool border: root.cfg.border !== false

    function block(id) {
        return root.cfg[id] || ({});
    }
    function active(id) {
        return root.masterEnabled && root.block(id).enabled === true;
    }
}
