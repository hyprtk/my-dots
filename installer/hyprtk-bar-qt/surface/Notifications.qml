// Notification toast stack, via the shared NotifyData singleton.
//
// The daemon (and history) live in data/NotifyData.qml; this surface only
// renders the transient toasts. It is loaded by shell.qml (enabled unless
// HYPRTK_BAR_QT_NOTIFICATIONS=0).
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../data"

PanelWindow {
    id: toasts

    // Show on the focused monitor (captured when the first toast appears).
    property var targetScreen: null
    screen: targetScreen

    anchors.top: BarConfig.barPosition === "top"
    anchors.bottom: BarConfig.barPosition === "bottom"
    margins.top: BarConfig.barPosition === "top" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 8 : 0
    margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 8 : 0
    implicitWidth: 340
    implicitHeight: column.implicitHeight + 24
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: NotifyData.toasts.length > 0
    onVisibleChanged: if (visible) targetScreen = Screens.focused()

    function iconSource(n) {
        if (n.appIcon && String(n.appIcon).length)
            return Quickshell.iconPath(n.appIcon, "application-x-executable");
        return "";
    }
    function imageSource(n) {
        const img = n.image;
        if (!img || !String(img).length)
            return "";
        const s = String(img);
        return (s.startsWith("/") || s.startsWith("file://")) ? (s.startsWith("/") ? "file://" + s : s) : s;
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.opacity)

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: NotifyData.toasts

                delegate: Rectangle {
                    id: toast
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: body.implicitHeight + 16
                    radius: 10
                    color: Theme.alpha(Theme.accent2, 0.15)
                    border.color: Theme.alpha(Theme.accent, 0.5)
                    border.width: 1

                    RowLayout {
                        id: body
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Image {
                            Layout.alignment: Qt.AlignTop
                            visible: source !== ""
                            source: toasts.iconSource(toast.modelData)
                            sourceSize.width: 28
                            sourceSize.height: 28
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: toast.modelData.appName || "Notification"
                                color: Theme.dim
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }
                            Text {
                                text: toast.modelData.summary || ""
                                color: Theme.accent
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }
                            Text {
                                text: toast.modelData.body || ""
                                color: Theme.foreground
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }
                            Image {
                                Layout.fillWidth: true
                                visible: source !== ""
                                source: toasts.imageSource(toast.modelData)
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 300
                                Layout.preferredHeight: visible ? Math.min(160, implicitHeight) : 0
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: (toast.modelData.actions || []).length > 0
                                Item { Layout.fillWidth: true }
                                Repeater {
                                    model: toast.modelData.actions || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: taText.implicitWidth + 18
                                        implicitHeight: 24
                                        radius: 6
                                        color: taHover.hovered ? Theme.alpha(Theme.accent2, 0.3) : Theme.alpha(Theme.accent, 0.25)
                                        Text { id: taText; anchors.centerIn: parent; text: modelData.text || ""; color: Theme.foreground; font.pixelSize: 11 }
                                        HoverHandler { id: taHover }
                                        TapHandler { onTapped: modelData.invoke() }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: "\u00d7"
                            color: Theme.dim
                            font.pixelSize: 13
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotifyData.dropToast(toast.modelData)
                            }
                        }
                    }

                    Timer {
                        running: true
                        interval: {
                            const t = toast.modelData.expireTimeout;
                            return t && t > 0 ? Math.max(1500, t) : NotifyData.defaultTimeout;
                        }
                        onTriggered: NotifyData.dropToast(toast.modelData)
                    }
                }
            }
        }
    }
}
