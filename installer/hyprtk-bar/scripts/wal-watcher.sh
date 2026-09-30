#!/bin/bash
# wal-watcher.sh — watches awww for wallpaper changes and runs pywal.
#
# Standalone variant: uses the bar's bundled change-icons.sh (no ~/hyprtk
# dependency). Started by install.sh's Hyprland autostart block so a wallpaper
# set by any tool (Theme Manager, waypaper, awww img, …) also regenerates the
# palette, copied configs and icon colours.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Bundled wal (vendored pywal16): prefer $HYPRTK_WAL (set by hyprtk-bar), then
# the launcher beside this install, then PATH. The watcher autostarts under
# Hyprland's minimal PATH, so the beside-this-install path matters here.
WAL="${HYPRTK_WAL:-}"
if [ -z "$WAL" ] && [ -x "$SCRIPT_DIR/../venv/bin/wal" ]; then
    WAL="$SCRIPT_DIR/../venv/bin/wal"
fi
WAL="${WAL:-wal}"

LAST_WALL=""

# Progress fifo lives in the private runtime dir (mode 600) so another user
# cannot plant/hijack it; the previous reader is reaped before restarting.
WOB_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WOB_FIFO="$WOB_DIR/wobpipe"
WOB_PID="$WOB_DIR/hyprtk-wob.pid"

while true; do
    CURRENT=$(awww query 2>/dev/null | sed -n 's/.*image: //p')
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$LAST_WALL" ] && [ -f "$CURRENT" ]; then
        echo "Wallpaper changed: $CURRENT"
        LAST_WALL="$CURRENT"
        # Run pywal and sync colours (the wallpaper is already set by the caller)
        "$WAL" -i "$CURRENT" -n -q
        [ -f ~/.cache/wal/colors-wofi.css ]      && cp ~/.cache/wal/colors-wofi.css   ~/.config/wofi/style.css
        [ -f ~/.cache/wal/wob.ini ]              && cp ~/.cache/wal/wob.ini            ~/.config/wob/wob.ini
        [ -f ~/.cache/wal/hyprland-colors.conf ] && cp ~/.cache/wal/hyprland-colors.conf ~/.config/hypr/hyprland-colors.conf
        cp "$CURRENT" ~/.cache/current-wallpaper.png 2>/dev/null
        hyprctl reload 2>/dev/null
        "$SCRIPT_DIR/change-icons.sh"
        # hyprtk-bar owns the taskbar + notifications bus
        [ -r "$WOB_PID" ] && kill "$(cat "$WOB_PID")" 2>/dev/null
        pkill -f "tail -f $WOB_FIFO" 2>/dev/null
        rm -f "$WOB_FIFO"
        if mkfifo -m 600 "$WOB_FIFO" 2>/dev/null; then
            tail -f "$WOB_FIFO" 2>/dev/null | wob -c ~/.config/wob/wob.ini >/dev/null 2>&1 &
            echo "$!" > "$WOB_PID"
        fi
    fi
    sleep 1
done
