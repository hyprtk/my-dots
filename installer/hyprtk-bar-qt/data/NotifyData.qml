// Notification daemon + history, shared by the bar bell, the toast stack and
// the notification center.
//
// The Qt bar owns org.freedesktop.Notifications by default (the GTK bar's
// daemon must not be running). Set HYPRTK_BAR_QT_NOTIFICATIONS=0 (or
// notifications.enabled=false) to opt out.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "."

Singleton {
    id: root

    readonly property bool enabled:
        Quickshell.env("HYPRTK_BAR_QT_NOTIFICATIONS") !== "0"
        && BarConfig.notifications.enabled !== false

    // Shared notifications config block (max_stored / default_timeout).
    readonly property int maxStored: BarConfig.notifications.max_stored || 50
    readonly property int defaultTimeout: BarConfig.notifications.default_timeout || 5000

    // History (all tracked notifications, newest last) + arrival timestamps.
    property var tracked: []
    property var stamps: ({})
    property int unread: 0

    // Transient toasts (a small subset of `tracked` shown briefly).
    property var toasts: []

    // The bar is the intended daemon: stop known competitors (dunst/mako/swaync/
    // xfce4-notifyd) BEFORE registering, or they keep org.freedesktop.Notifications.
    property bool competitorsCleared: false
    Process {
        id: killProc
        running: root.enabled && !root.competitorsCleared
        command: ["sh", "-c", "for b in dunst mako swaync xfce4-notifyd; do pkill -x \"$b\" 2>/dev/null || true; done"]
        onExited: (code, status) => root.competitorsCleared = true
    }

    Loader {
        active: root.enabled && root.competitorsCleared
        sourceComponent: Component {
            NotificationServer {
                id: srv
                keepOnReload: false
                onNotification: (n) => {
                    n.tracked = true;
                    root.unread += 1;
                    const m = Object.assign({}, root.stamps);
                    m[n.id] = Date.now();
                    root.stamps = m;
                    root.tracked = root.tracked.concat([n]).slice(-root.maxStored);
                    root._pushToast(n);
                }
            }
        }
    }

    function _pushToast(n) {
        const next = root.toasts.filter(x => x !== n);
        next.unshift(n);
        root.toasts = next.slice(0, 3);
    }
    function dropToast(n) {
        root.toasts = root.toasts.filter(x => x !== n);
    }

    function markRead() {
        root.unread = 0;
    }
    function remove(n) {
        n.dismiss();
        root.tracked = root.tracked.filter(x => x !== n);
    }
    function clearAll() {
        const items = root.tracked.slice();
        for (let i = 0; i < items.length; i++)
            items[i].dismiss();
        root.tracked = [];
    }

    // Newest-first history for the center (capped at max_stored).
    function history() {
        return root.tracked.slice().reverse().slice(0, root.maxStored);
    }

    function ago(id) {
        const t = root.stamps[id];
        if (!t)
            return "";
        const s = Math.max(0, Math.floor((Date.now() - t) / 1000));
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
