#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WALLPAPER="$1"
[ -f "$WALLPAPER" ] || exit 1

# Bundled wal (vendored pywal16): prefer $HYPRTK_WAL (set by hyprtk-bar), then
# the launcher beside this install, then PATH.
WAL="${HYPRTK_WAL:-}"
if [ -z "$WAL" ] && [ -x "$SCRIPT_DIR/../venv/bin/wal" ]; then
    WAL="$SCRIPT_DIR/../venv/bin/wal"
fi
WAL="${WAL:-wal}"

# Set wallpaper (ensure the daemon is running first — a standalone install may
# not have started it). Prefer awww, fall back to swww.
if command -v awww >/dev/null 2>&1; then
    pgrep -x awww-daemon >/dev/null 2>&1 || { setsid awww-daemon >/dev/null 2>&1 & sleep 0.4; }
    awww img "$WALLPAPER" --transition-type fade --transition-duration 2 --transition-fps 60 2>/dev/null
elif command -v swww >/dev/null 2>&1; then
    pgrep -x swww-daemon >/dev/null 2>&1 || { setsid swww-daemon >/dev/null 2>&1 & sleep 0.4; }
    swww img "$WALLPAPER" --transition-type fade --transition-duration 2 --transition-fps 60 2>/dev/null
fi

# Run pywal
"$WAL" -i "$WALLPAPER" -n -q
[ -f ~/.cache/wal/colors-wofi.css ]      && cp ~/.cache/wal/colors-wofi.css   ~/.config/wofi/style.css
[ -f ~/.cache/wal/wob.ini ]              && cp ~/.cache/wal/wob.ini            ~/.config/wob/wob.ini
[ -f ~/.cache/wal/hyprland-colors.conf ] && cp ~/.cache/wal/hyprland-colors.conf ~/.config/hypr/hyprland-colors.conf

cp "$WALLPAPER" ~/.cache/current-wallpaper.png 2>/dev/null
hyprctl reload 2>/dev/null
"$SCRIPT_DIR/change-icons.sh"
# hyprtk-bar owns the taskbar + notifications bus. Keep the progress fifo in
# the private runtime dir (mode 600) so another user can't plant/hijack it.
WOB_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WOB_FIFO="$WOB_DIR/wobpipe"
WOB_PID="$WOB_DIR/hyprtk-wob.pid"
[ -r "$WOB_PID" ] && kill "$(cat "$WOB_PID")" 2>/dev/null
pkill -f "tail -f $WOB_FIFO" 2>/dev/null
rm -f "$WOB_FIFO"
if mkfifo -m 600 "$WOB_FIFO" 2>/dev/null; then
    tail -f "$WOB_FIFO" 2>/dev/null | wob -c ~/.config/wob/wob.ini >/dev/null 2>&1 &
    echo "$!" > "$WOB_PID"
fi
