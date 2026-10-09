// Themed combo box with a themed popup list.
import QtQuick
import QtQuick.Controls.Basic
import "../theme"

ComboBox {
    id: root

    implicitHeight: 30
    implicitWidth: 150
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    leftPadding: 9
    rightPadding: 26

    contentItem: Text {
        text: root.displayText
        font: root.font
        color: Theme.foreground
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 9
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf078"
        color: Theme.dim
        font.pixelSize: 10
    }

    background: Rectangle {
        radius: 6
        color: Theme.alpha(Theme.background, 0.6)
        border.width: 1
        border.color: root.activeFocus ? Theme.accent : Theme.alpha(Theme.accent2, 0.30)
    }

    delegate: ItemDelegate {
        id: item
        required property var modelData
        required property int index
        width: root.width
        implicitHeight: 28
        highlighted: root.highlightedIndex === index
        contentItem: Text {
            text: item.modelData
            color: Theme.foreground
            font.pixelSize: Theme.fontSize
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: item.highlighted ? Theme.alpha(Theme.accent2, 0.20) : "transparent"
        }
    }

    popup: Popup {
        y: root.height + 2
        width: root.width
        implicitHeight: Math.min(260, contentItem.implicitHeight + 2)
        padding: 1
        background: Rectangle {
            radius: 8
            color: Theme.background
            border.width: 1
            border.color: Theme.alpha(Theme.accent2, 0.35)
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }
    }
}
