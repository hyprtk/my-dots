import QtQuick
import "../../components"
import "../../state"

BarIconButton {
    glyph: "\uf013"
    tooltip: "Settings"
    active: UiState.settingsOpen
    onActivated: UiState.settingsOpen = !UiState.settingsOpen
}
