#!/bin/bash
WALLPAPER="$1"
[ -f "$WALLPAPER" ] || exit 1

# Lock to prevent wal-watcher from double-processing
LOCK="$HOME/.cache/wal/.wallpaper-change.lock"
touch "$LOCK"
trap "rm -f '$LOCK'" EXIT

awww img "$WALLPAPER" --transition-type fade --transition-duration 2 --transition-fps 60
wal -i "$WALLPAPER" -n -q
[ -f ~/.cache/wal/colors-wofi.css ]       && cp ~/.cache/wal/colors-wofi.css       ~/.config/wofi/style.css
[ -f ~/.cache/wal/wob.ini ]               && cp ~/.cache/wal/wob.ini               ~/.config/wob/wob.ini
[ -f ~/.cache/wal/dunstrc ]               && cp ~/.cache/wal/dunstrc                ~/.config/dunst/dunstrc
[ -f ~/.cache/wal/hyprland-colors.conf ]  && cp ~/.cache/wal/hyprland-colors.conf  ~/.config/hypr/hyprland-colors.conf
[ -f ~/.cache/wal/colors-matuwall.json ]  && cp ~/.cache/wal/colors-matuwall.json  ~/.config/matuwall/colors.json
[ -f ~/.cache/wal/colors-swaylock.conf ]  && cp ~/.cache/wal/colors-swaylock.conf  ~/.config/swaylock/config
bash ~/hyprtk/hypr/scripts/generate-aero-colors.sh
# Update hyprlock background
cp "$WALLPAPER" ~/.cache/current-wallpaper.png 2>/dev/null
hyprctl reload 2>/dev/null
killall waybar 2>/dev/null; ~/hyprtk/configs/waybar/launch.sh
~/hyprtk/configs/papirus-icons/scripts/change-icons.sh
pkill dunst 2>/dev/null; dunst &
pkill wob 2>/dev/null
rm -f /tmp/wobpipe && mkfifo /tmp/wobpipe
tail -f /tmp/wobpipe | wob -c ~/.config/wob/wob.ini &
