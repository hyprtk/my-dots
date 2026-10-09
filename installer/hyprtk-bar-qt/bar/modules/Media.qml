// Media (MPRIS) module: now-playing text plus transport controls.
//
// Optional extra — the reference GTK bar has no media module. Built on
// Quickshell's MPRIS service; hidden unless at least one player is present.
// Config block `media`: enabled / show_controls / show_text / max_length /
// text_width.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../theme"
import "../../data"

Item {
    id: media

    readonly property var mblock: BarConfig.media
    readonly property var playerList: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
    // Prefer a playing player, otherwise the first one found.
    readonly property var player: {
        const ps = media.playerList;
        if (!ps || ps.length === 0)
            return null;
        return ps.find(p => p.isPlaying) || ps[0];
    }
    readonly property bool showControls: media.mblock.show_controls !== false
    readonly property bool showText: media.mblock.show_text !== false
    readonly property int maxLen: media.mblock.max_length !== undefined ? media.mblock.max_length : 48
    readonly property int textWidth: media.mblock.text_width !== undefined ? media.mblock.text_width : 180

    visible: BarConfig.media.enabled !== false && media.player !== null
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    function trackText() {
        if (!media.player)
            return "";
        const t = media.player.trackTitle || "";
        const a = media.player.trackArtist || media.player.trackArtists || "";
        let s = (t && a) ? (t + " \u2014 " + a) : (t || a);
        if (media.maxLen > 0 && s.length > media.maxLen)
            s = s.slice(0, media.maxLen - 1) + "\u2026";
        return s;
    }
    function fullText() {
        if (!media.player)
            return "";
        const parts = [];
        if (media.player.trackTitle) parts.push(media.player.trackTitle);
        const a = media.player.trackArtist || media.player.trackArtists;
        if (a) parts.push(a);
        if (media.player.trackAlbum) parts.push(media.player.trackAlbum);
        return parts.join("\n") || (media.player.identity || "");
    }

    component Glyph: Text {
        id: g
        property string glyph: ""
        property bool clickable: true
        property color base: Theme.foreground
        signal tapped()
        text: g.glyph
        color: !g.clickable ? Theme.alpha(Theme.foreground, 0.3)
             : (gHover.hovered ? Theme.accent : g.base)
        font.family: BarConfig.glyphFont
        font.pixelSize: BarConfig.iconSize(BarConfig.fontSize(11))
        HoverHandler { id: gHover }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: g.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (g.clickable) g.tapped()
        }
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Glyph {
            visible: media.showControls && media.player !== null && media.player.canGoPrevious
            glyph: "\uf048"
            onTapped: media.player.previous()
        }
        Glyph {
            visible: media.showControls && media.player !== null
                && (media.player.canControl || media.player.canTogglePlaying)
            glyph: (media.player !== null && media.player.isPlaying) ? "\uf04c" : "\uf04b"
            base: Theme.accent
            onTapped: media.player.togglePlaying()
        }
        Glyph {
            visible: media.showControls && media.player !== null && media.player.canGoNext
            glyph: "\uf051"
            onTapped: media.player.next()
        }
        Text {
            visible: media.showText && media.trackText().length > 0
            text: media.trackText()
            color: Theme.foreground
            font.pixelSize: BarConfig.fontSize(11)
            font.family: BarConfig.fontFamily("Noto Sans")
            elide: Text.ElideRight
            Layout.preferredWidth: Math.min(implicitWidth, media.textWidth)
        }
    }

    HoverHandler {
        id: mediaHover
        onHoveredChanged: (mediaHover.hovered && media.fullText().length)
            ? Tooltips.showTip(media, media.fullText())
            : Tooltips.hideTip()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (media.player && media.player.canRaise)
                media.player.raise();
        }
    }
}
