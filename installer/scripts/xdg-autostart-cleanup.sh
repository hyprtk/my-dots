#!/bin/bash
# ── Suppress cross-desktop XDG autostart entries ─────────────────────────────
# Sessions launched through uwsm run `systemd-xdg-autostart`, which starts every
# /etc/xdg/autostart entry whose OnlyShowIn/NotShowIn allows the current
# desktop. Distro defaults aimed at another desktop therefore also run under
# Hyprland. Fedora Xfce's dnfdragora-updater crashes there (python SIGABRT) and
# pops an ABRT "Oops!" dialog on every login.
#
# A per-user Hidden=true override disables an entry without touching the system
# file, so the other desktop (Xfce) keeps it. Only entries listed here are
# touched; anything the user already overrode is left alone.
set -u

AUTOSTART="$HOME/.config/autostart"
mkdir -p "$AUTOSTART"

# entry id → why it is suppressed in the Hyprland session
declare -A SUPPRESS=(
    [org.mageia.dnfdragora-updater]="Fedora Xfce package-update notifier; crashes under Hyprland (SIGABRT → ABRT dialog)"
)

suppressed=0
for name in "${!SUPPRESS[@]}"; do
    [ -f "/etc/xdg/autostart/$name.desktop" ] || continue
    override="$AUTOSTART/$name.desktop"
    if [ -f "$override" ] && grep -qi '^Hidden=true' "$override"; then
        continue
    fi
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$name"
        printf 'Comment=%s\n' "${SUPPRESS[$name]}"
        printf 'Hidden=true\n'
    } > "$override"
    echo "suppressed autostart entry: $name"
    suppressed=$((suppressed + 1))
done

if [ "$suppressed" -eq 0 ]; then
    echo "no cross-desktop autostart entries to suppress"
fi
exit 0
