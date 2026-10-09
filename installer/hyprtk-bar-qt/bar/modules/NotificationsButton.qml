// Bell button with an unread badge; toggles the notification center.
import QtQuick
import Quickshell
import "../../theme"
import "../../components"
import "../../state"
import "../../data"

Item {
    id: notifBtn
    implicitWidth: 22
    implicitHeight: 22
    visible: BarConfig.notifications.enabled !== false

    // Our monitor (the bar window's screen), so the center opens here.
    readonly property string screenName: (QsWindow.window && QsWindow.window.screen) ? QsWindow.window.screen.name : ""

    // Register our window-relative position so the notification center can line
    // up under the bell (within the bar), on this monitor.
    function _register() { BarAnchors.setNotif(mapToItem(null, 0, 0).x, width, notifBtn.screenName); }
    Component.onCompleted: _register()
    onXChanged: _register()
    onWidthChanged: _register()
    onScreenNameChanged: _register()

    BarIconButton {
        anchors.fill: parent
        glyph: "\uf0f3"
        tooltip: "Notifications" + (NotifyData.unread > 0 ? " (" + NotifyData.unread + " unread)" : "")
        active: UiState.notificationCenterOpen
        onActivated: {
            UiState.notificationCenterOpen = !UiState.notificationCenterOpen;
            if (UiState.notificationCenterOpen)
                NotifyData.markRead();
        }
    }

    Rectangle {
        visible: NotifyData.unread > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -4
        anchors.rightMargin: -4
        width: Math.max(14, badgeText.implicitWidth + 6)
        height: 14
        radius: 7
        color: Theme.err
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: NotifyData.unread > 9 ? "9+" : String(NotifyData.unread)
            color: "#000000"
            font.pixelSize: 9
        }
    }
}
