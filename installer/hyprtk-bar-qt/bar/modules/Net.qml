// Network module: receive/transmit rates + a rolling sparkline each.
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../data"
import "../../components"

RowLayout {
    id: root
    spacing: 8

    readonly property int fs: BarConfig.fontSize(11)

    RowLayout {
        spacing: 4
        Text { text: "\uf063"; color: Theme.accent2; font.family: BarConfig.glyphFont; font.pixelSize: BarConfig.iconSize(root.fs) }
        Sparkline {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 16
            values: SysData.rxHist
            color: Theme.accent2      // autoscale (scale 0)
        }
        Text {
            text: SysData.humanBytes(SysData.rx)
            color: Theme.foreground
            font.pixelSize: root.fs
            Layout.preferredWidth: 58
        }
    }

    RowLayout {
        spacing: 4
        Text { text: "\uf062"; color: Theme.accent; font.family: BarConfig.glyphFont; font.pixelSize: BarConfig.iconSize(root.fs) }
        Sparkline {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 16
            values: SysData.txHist
            color: Theme.accent
        }
        Text {
            text: SysData.humanBytes(SysData.tx)
            color: Theme.foreground
            font.pixelSize: root.fs
            Layout.preferredWidth: 58
        }
    }
}
