#!/bin/sh
# ── hyprtk-session — start the Wayland session with a D-Bus session bus ──────
# systemd distros get a per-session D-Bus bus from pam_systemd, so nothing is
# needed. Non-systemd distros (Void/runit, Alpine/OpenRC) start none at all,
# which breaks GSettings/dconf (e.g. hyprcursor's cursor-theme lookup),
# xdg-desktop-portal and the notification daemon. Launch the compositor under
# dbus-run-session in that case.
#
# Usage (from the .desktop file): hyprtk-session <compositor command...>
set -u

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$@"
fi
exec "$@"
