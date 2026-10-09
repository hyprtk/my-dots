import QtQuick
import Quickshell
import "../../components"
import "../../state"
import "../../data"

BarIconButton {
    id: startBtn
    visible: BarConfig.center.start_button !== false
    glyph: BarConfig.center.start_glyph || "\uf015"
    tooltip: "Open menu"
    active: UiState.startMenuOpen

    // The bar window's monitor, so the menu opens on the clicked screen.
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    onActivated: {
        BarAnchors.setMenuScreen(startBtn.screenName);
        UiState.startMenuOpen = !UiState.startMenuOpen;
    }
}
