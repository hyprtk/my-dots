// Month calendar popup (a shared layer-shell popup anchored to the clock).
import QtQuick
import Quickshell
import "../theme"
import "../data"

PopupWindow {
    id: cal

    property var anchorWin: null

    readonly property var today: new Date()
    readonly property int year: Cal.view.getFullYear()
    readonly property int month: Cal.view.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property int firstWeekday: new Date(year, month, 1).getDay()  // 0 = Sunday
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"]
    readonly property var weekdayNames: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    visible: Cal.show && Cal.target !== null
    color: "transparent"
    implicitWidth: 244
    implicitHeight: 236
    grabFocus: true
    onClosed: Cal.close()

    Shortcut {
        sequence: "Escape"
        onActivated: Cal.close()
    }

    anchor.window: cal.anchorWin
    anchor.item: Cal.target
    anchor.rect: Qt.rect(0, Cal.target ? Cal.target.height : 0, Cal.target ? Cal.target.width : 0, 1)
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Math.max(0.96, Theme.opacity))
        border.width: 1
        border.color: Theme.alpha(Theme.accent2, 0.25)

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Row {
                width: parent.width
                Text {
                    text: "\uf053"
                    color: Theme.accent2
                    font.family: BarConfig.glyphFont
                    font.pixelSize: 12
                    width: 22; height: 18
                    horizontalAlignment: Text.AlignHCenter
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Cal.prev() }
                }
                Text {
                    text: cal.monthNames[cal.month] + " " + cal.year
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 13
                    width: parent.width - 44
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: "\uf054"
                    color: Theme.accent2
                    font.family: BarConfig.glyphFont
                    font.pixelSize: 12
                    width: 22; height: 18
                    horizontalAlignment: Text.AlignHCenter
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Cal.next() }
                }
            }

            Grid {
                columns: 7
                spacing: 2
                Repeater {
                    model: cal.weekdayNames
                    delegate: Text {
                        required property string modelData
                        text: modelData
                        color: Theme.dim
                        font.pixelSize: 10
                        width: 30
                        height: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Repeater {
                    model: 42
                    delegate: Text {
                        required property int index
                        readonly property int day: index - cal.firstWeekday + 1
                        readonly property bool valid: day >= 1 && day <= cal.daysInMonth
                        readonly property bool isToday: valid && day === cal.today.getDate()
                            && cal.month === cal.today.getMonth() && cal.year === cal.today.getFullYear()
                        text: valid ? String(day) : ""
                        color: isToday ? Theme.accent : Theme.foreground
                        font.bold: isToday
                        font.pixelSize: 11
                        width: 30
                        height: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
