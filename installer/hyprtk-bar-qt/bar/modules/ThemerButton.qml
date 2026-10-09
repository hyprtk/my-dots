import QtQuick
import Quickshell
import "../../components"
import "../../state"
import "../../data"

BarIconButton {
    id: themerBtn
    glyph: "\uf1fc"
    tooltip: "Theme Manager"
    visible: BarConfig.themer.enabled !== false
    active: UiState.themerOpen
    onActivated: UiState.themerOpen = !UiState.themerOpen

    // Our monitor (the bar window's screen), so the panel opens here.
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    // Register our window-relative position so the panel lines up under us.
    function _register() { BarAnchors.setThemer(mapToItem(null, 0, 0).x, width, themerBtn.screenName); }
    Component.onCompleted: _register()
    onXChanged: _register()
    onWidthChanged: _register()
    onScreenNameChanged: _register()
}
