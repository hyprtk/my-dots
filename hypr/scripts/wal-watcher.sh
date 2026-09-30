#!/bin/bash
# wal-watcher.sh — watches awww for wallpaper changes and runs pywal

LAST_WALL=""

# Progress fifo lives in the private runtime dir (mode 600) so another user
# cannot plant/hijack it.
WOB_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WOB_FIFO="$WOB_DIR/wobpipe"
WOB_PID="$WOB_DIR/hyprtk-wob.pid"

while true; do
    CURRENT=$(awww query 2>/dev/null | sed -n 's/.*image: //p')
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$LAST_WALL" ] && [ -f "$CURRENT" ]; then
        echo "Wallpaper changed: $CURRENT"
        LAST_WALL="$CURRENT"
        # Run pywal and sync colors (skip swww since awww already set it)
        wal -i "$CURRENT" -n -q
        [ -f ~/.cache/wal/colors-wofi.css ]      && cp ~/.cache/wal/colors-wofi.css   ~/.config/wofi/style.css
        [ -f ~/.cache/wal/wob.ini ]              && cp ~/.cache/wal/wob.ini            ~/.config/wob/wob.ini
        [ -f ~/.cache/wal/hyprland-colors.conf ] && cp ~/.cache/wal/hyprland-colors.conf ~/.config/hypr/hyprland-colors.conf
        #sudo cp "$CURRENT" /usr/share/sddm/themes/catppuccin/backgrounds/current-wall.jpg 2>/dev/null
        #bash ~/.config/hypr/scripts/sddm-colors.sh
        cp "$CURRENT" ~/.cache/current-wallpaper.png 2>/dev/null
        hyprctl reload 2>/dev/null
        ~/hyprtk/assets/papirus-icons/scripts/change-icons.sh
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
