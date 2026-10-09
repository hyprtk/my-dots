import QtQuick
import Quickshell
import "../../components"
import "../../state"
import "../../data"

BarIconButton {
    id: qsBtn
    glyph: "\uf013"
    tooltip: "Quick settings"
    visible: BarConfig.quicksettings.enabled !== false
    active: UiState.quickSettingsOpen
    onActivated: UiState.quickSettingsOpen = !UiState.quickSettingsOpen

    // Our monitor (the bar window's screen), so the flyout opens here.
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    // Register our window-relative position so the flyout lines up under us.
    function _register() { BarAnchors.setQs(mapToItem(null, 0, 0).x, width, qsBtn.screenName); }
    Component.onCompleted: _register()
    onXChanged: _register()
    onWidthChanged: _register()
    onScreenNameChanged: _register()
}
