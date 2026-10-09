// The bar surface: a frosted panel whose module row is data-driven from
// Config.layoutLeft / layoutCenter / layoutRight. Right-click opens the menu.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../config"
import "../state"
import "../data"
import "../components"
import "modules"

Rectangle {
    id: root

    readonly property real bgOpacity: Config.opacity >= 0 ? Config.opacity : Theme.opacity
    readonly property var leftMods: BarConfig.layoutLeft.length ? BarConfig.layoutLeft : Config.layoutLeft
    readonly property var centerMods: BarConfig.layoutCenter.length ? BarConfig.layoutCenter : Config.layoutCenter
    readonly property var rightMods: BarConfig.layoutRight.length ? BarConfig.layoutRight : Config.layoutRight

    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, root.bgOpacity)
    radius: BarConfig.radius

    // Single shared tooltip + context-menu surfaces (modules register via the
    // Tooltips / PopupMenu singletons).
    BarTooltip { anchorWin: root.QsWindow.window }
    BarMenuPopup { anchorWin: root.QsWindow.window }
    BarCalendar { anchorWin: root.QsWindow.window }

    // Animated border (shared `theme.border_animation` + `animations` mode/speed).
    readonly property bool borderAnim: BarConfig.theme.border_animation !== false && Config.uiAnimations
    // Prefer the real Hyprland animation period (backend); fall back to a
    // local estimate when the hypr config is unavailable.
    readonly property int borderMs: {
        if (HyprAnim.periodMs > 0)
            return HyprAnim.periodMs;
        const mode = BarConfig.animations.mode || "high";
        if (mode === "custom")
            return Math.max(200, Math.round(4000 / Math.max(1, BarConfig.animations.speed || 15)));
        return mode === "low" ? 3200 : 1400;
    }
    border.width: BarConfig.borderWidth
    border.color: Theme.accent
    SequentialAnimation on border.color {
        running: root.borderAnim
        loops: Animation.Infinite
        ColorAnimation { to: Theme.accent2; duration: root.borderMs; easing.type: Easing.InOutSine }
        ColorAnimation { to: Theme.accent; duration: root.borderMs; easing.type: Easing.InOutSine }
    }

    // Maps a layout entry to its module component.
    component ModuleChooser: DelegateChooser {
        role: "modelData"
        DelegateChoice { roleValue: "start_button"; delegate: StartButton {} }
        DelegateChoice { roleValue: "quicklinks"; delegate: Quicklinks {} }
        DelegateChoice { roleValue: "workspaces"; delegate: Workspaces {} }
        DelegateChoice { roleValue: "tasklist"; delegate: Tasklist {} }
        DelegateChoice { roleValue: "window"; delegate: ActiveWindow {} }
        DelegateChoice { roleValue: "updates"; delegate: Updates {} }
        DelegateChoice { roleValue: "net"; delegate: Net {} }
        DelegateChoice { roleValue: "tray"; delegate: Tray {} }
        DelegateChoice { roleValue: "kbstate"; delegate: KbState {} }
        DelegateChoice { roleValue: "notifications"; delegate: NotificationsButton {} }
        DelegateChoice { roleValue: "clock"; delegate: Clock {} }
        DelegateChoice { roleValue: "media"; delegate: Media {} }
        DelegateChoice { roleValue: "sysmon"; delegate: SysMonitor {} }
        DelegateChoice { roleValue: "themer"; delegate: ThemerButton {} }
        DelegateChoice { roleValue: "settings"; delegate: SettingsButton {} }
        DelegateChoice { roleValue: "quicksettings"; delegate: QuickSettingsButton {} }
        DelegateChoice { delegate: Item {} }
    }

    // the bar window's monitor, so popups open on the clicked screen
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    // right-click anywhere on the bar opens the context menu
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: (mouse) => {
            UiState.barMenuX = mouse.x;
            BarAnchors.setBarMenuScreen(root.screenName);
            UiState.barMenuOpen = true;
        }
    }

    // Sections are anchored independently so the centre sits on the bar's
    // centre (like Gtk.CenterBox), independent of the left/right widths.
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: root.leftMods
            delegate: ModuleChooser {}
        }
    }

    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: root.centerMods
            delegate: ModuleChooser {}
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: root.rightMods
            delegate: ModuleChooser {}
        }
    }
}
