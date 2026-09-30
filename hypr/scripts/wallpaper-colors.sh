#!/bin/bash
WALLPAPER="$1"
[ -f "$WALLPAPER" ] || exit 1

# The awww wrapper (~/.local/bin/awww) already applied the wallpaper with the
# real binary before calling this script; do NOT call `awww` here or the
# wrapper recurses (it runs this after every `awww img`).

# Run pywal
wal -i "$WALLPAPER" -n -q
[ -f ~/.cache/wal/colors-wofi.css ]      && cp ~/.cache/wal/colors-wofi.css   ~/.config/wofi/style.css
[ -f ~/.cache/wal/wob.ini ]              && cp ~/.cache/wal/wob.ini            ~/.config/wob/wob.ini
[ -f ~/.cache/wal/hyprland-colors.conf ] && cp ~/.cache/wal/hyprland-colors.conf ~/.config/hypr/hyprland-colors.conf

cp "$WALLPAPER" ~/.cache/current-wallpaper.png 2>/dev/null
hyprctl reload 2>/dev/null
~/hyprtk/assets/papirus-icons/scripts/change-icons.sh
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
