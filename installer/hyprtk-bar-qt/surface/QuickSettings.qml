// Quick settings flyout: volume, brightness, Wi-Fi, Bluetooth + shortcuts.
//
// State is read/set with the same session tools the GTK bar used — wpctl
// (WirePlumber), brightnessctl, nmcli and bluetoothctl — via Quickshell Process.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"
import "../state"
import "../components"
import "../data"

PanelWindow {
    id: qs

    readonly property real screenW: qs.screen ? qs.screen.width : 0
    readonly property var insets: BarGeom.insets(qs.screenW)
    // Right edge of the quick-settings button in screen coords (fallback: bar right inset).
    readonly property real btnRight: BarAnchors.qsX >= 0
        ? qs.insets.left + BarAnchors.qsX + BarAnchors.qsW
        : qs.screenW - qs.insets.right
    // Right-align the flyout under the button, clamped inside the bar's extent.
    readonly property real leftMargin: Math.max(
        qs.insets.left,
        Math.min(qs.btnRight - qs.implicitWidth,
                 qs.screenW - qs.insets.right - qs.implicitWidth))

    anchors.top: BarConfig.barPosition === "top"
    anchors.bottom: BarConfig.barPosition === "bottom"
    anchors.left: true
    margins.top: BarConfig.barPosition === "top" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.bottom: BarConfig.barPosition === "bottom" ? BarConfig.barHeight + BarConfig.gapOut + BarConfig.gapIn + 6 : 0
    margins.left: qs.leftMargin
    implicitWidth: 340
    implicitHeight: panel.implicitHeight + 28
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    visible: UiState.quickSettingsOpen

    // Open on the button's monitor (registered by the module), else the focused one.
    property var targetScreen: null
    screen: Screens.byName(BarAnchors.qsScreen) || targetScreen

    IpcHandler {
        target: "quicksettings"
        function toggle() { UiState.quickSettingsOpen = !UiState.quickSettingsOpen; }
        function open() { UiState.quickSettingsOpen = true; }
        function close() { UiState.quickSettingsOpen = false; }
    }

    // Reveal animation (gated by the shared animations switch).
    property real reveal: 0
    readonly property int animMs: Config.uiAnimations ? Config.animationDuration : 0
    Behavior on reveal { NumberAnimation { duration: qs.animMs; easing.type: Easing.OutCubic } }
    onVisibleChanged: {
        reveal = visible ? 1 : 0;
        if (visible) {
            targetScreen = Screens.focused();
            refresh();
        }
    }
    // Re-probe while open so external changes (media keys, other apps) show up.
    Timer { running: qs.visible; interval: 5000; repeat: true; onTriggered: qs.refresh() }

    property int volume: 0
    property bool muted: false
    property int micVolume: 0
    property bool micMuted: false
    property int brightness: 100
    property bool hasBacklight: false
    property bool brightnessProbed: false
    property bool wifiOn: false
    property bool btOn: false

    function refresh() {
        qs.brightnessProbed = false;
        volGet.running = true;
        micGet.running = true;
        brightGet.running = true;
        wifiGet.running = true;
        btGet.running = true;
    }
    // ── readers ────────────────────────────────────────────────────────
    Process {
        id: volGet
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/([0-9.]+)/);
                if (m)
                    qs.volume = Math.round(parseFloat(m[1]) * 100);
                qs.muted = /MUTED/.test(line);
            }
        }
    }
    Process {
        id: micGet
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/([0-9.]+)/);
                if (m)
                    qs.micVolume = Math.round(parseFloat(m[1]) * 100);
                qs.micMuted = /MUTED/.test(line);
            }
        }
    }
    Process {
        id: brightGet
        command: ["brightnessctl", "-m"]
        // brightnessctl exits 0 even for LED-class devices (keyboard lights),
        // so only accept a real backlight/kbd_backlight device. With no kernel
        // backlight (e.g. a desktop with an external monitor), fall back to
        // hyprsunset gamma, as the GTK bar does.
        stdout: SplitParser {
            onRead: line => {
                const f = line.split(",");
                if (f.length < 5 || (f[1] !== "backlight" && f[1] !== "kbd_backlight"))
                    return;
                const max = parseInt(f[4]);
                if (!(max > 0))
                    return;
                qs.brightness = Math.round(parseInt(f[3]) || 0);
                qs.hasBacklight = true;
                qs.brightnessProbed = true;
            }
        }
        onExited: (code) => {
            if (!qs.brightnessProbed)
                gammaGet.running = true;
        }
    }
    Process {
        id: gammaGet
        command: ["hyprctl", "hyprsunset", "profile"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/gamma[:\s=]+([0-9]+)\s*%?/i);
                if (m)
                    qs.brightness = Math.max(30, Math.min(parseInt(m[1]), 100));
            }
        }
        onExited: (code) => { qs.hasBacklight = false; }
    }
    Process {
        id: wifiGet
        command: ["nmcli", "radio", "wifi"]
        stdout: SplitParser {
            onRead: line => { qs.wifiOn = line.trim() === "enabled"; }
        }
    }
    Process {
        id: btGet
        command: ["bluetoothctl", "show"]
        stdout: SplitParser {
            onRead: line => {
                if (/Powered:\s+yes/.test(line))
                    qs.btOn = true;
                else if (/Powered:\s+no/.test(line))
                    qs.btOn = false;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.opacity)
        border.width: BarConfig.borderWidth
        border.color: Theme.accent
        SequentialAnimation on border.color {
            running: Chrome.animated
            loops: Animation.Infinite
            ColorAnimation { to: Theme.accent2; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
            ColorAnimation { to: Theme.accent; duration: Chrome.periodMs; easing.type: Easing.InOutSine }
        }
        opacity: qs.reveal
        transform: Translate { y: (1 - qs.reveal) * -8 }

        ColumnLayout {
            id: panel
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Quick Settings"
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 15
                    Layout.fillWidth: true
                }
                Text {
                    text: "\u00d7"
                    color: Theme.dim
                    font.pixelSize: 16
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UiState.quickSettingsOpen = false
                    }
                }
            }

            // volume
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: qs.muted ? "\u2716" : "\u266b"; color: Theme.foreground; font.pixelSize: 15 }
                TSlider {
                    id: vol
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: qs.volume
                    onMoved: {
                        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (value / 100).toFixed(2)]);
                    }
                }
                Text { text: qs.volume + "%"; color: Theme.foreground; font.pixelSize: 12; Layout.preferredWidth: 38 }
                Text {
                    text: qs.muted ? "unmute" : "mute"
                    color: Theme.accent2
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                            qs.refresh();
                        }
                    }
                }
            }

            // microphone
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: qs.micMuted ? "\uf131" : "\uf130"; color: Theme.foreground; font.family: BarConfig.glyphFont; font.pixelSize: 15 }
                TSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: qs.micVolume
                    onMoved: {
                        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "0"]);
                        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", (value / 100).toFixed(2)]);
                    }
                }
                Text { text: qs.micVolume + "%"; color: Theme.foreground; font.pixelSize: 12; Layout.preferredWidth: 38 }
                Text {
                    text: qs.micMuted ? "unmute" : "mute"
                    color: Theme.accent2
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                            qs.refresh();
                        }
                    }
                }
            }

            // brightness
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "\u263c"; color: Theme.warn; font.pixelSize: 15 }
                TSlider {
                    Layout.fillWidth: true
                    from: qs.hasBacklight ? 0 : 30
                    to: 100
                    stepSize: 1
                    value: qs.brightness
                    onMoved: {
                        if (qs.hasBacklight) {
                            Quickshell.execDetached(["brightnessctl", "set", Math.round(value) + "%"]);
                            qs.brightness = Math.round(value);
                        } else {
                            const g = Math.max(30, Math.round(value));
                            Quickshell.execDetached(["hyprctl", "hyprsunset", "gamma", String(g)]);
                            qs.brightness = g;
                        }
                    }
                }
                Text { text: qs.brightness + "%"; color: Theme.foreground; font.pixelSize: 12; Layout.preferredWidth: 38 }
            }

            // wifi
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Wi-Fi"; color: Theme.foreground; Layout.fillWidth: true }
                Toggle {
                    checked: qs.wifiOn
                    onColor: Theme.accent
                    offColor: Theme.accent2
                    onToggled: (v) => {
                        Quickshell.execDetached(["nmcli", "radio", "wifi", v ? "on" : "off"]);
                        qs.wifiOn = v;
                    }
                }
            }

            // bluetooth
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Bluetooth"; color: Theme.foreground; Layout.fillWidth: true }
                Toggle {
                    checked: qs.btOn
                    onColor: Theme.accent
                    offColor: Theme.accent2
                    onToggled: (v) => {
                        Quickshell.execDetached(["bluetoothctl", "power", v ? "on" : "off"]);
                        qs.btOn = v;
                    }
                }
            }

            // shortcuts
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TButton {
                    text: "Settings"
                    onClicked: {
                        UiState.settingsOpen = true;
                        UiState.quickSettingsOpen = false;
                    }
                }
                TButton {
                    text: "Lock"
                    onClicked: {
                        const cmd = MenuConfig.power("lock") || "hyprlock || loginctl lock-session";
                        Quickshell.execDetached(["sh", "-c", cmd]);
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
