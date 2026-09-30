#!/bin/bash
#
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

# Select wallpaper
selected=$(ls -1 ~/Pictures/Wallpapers | grep "png" | rofi -dmenu -config ~/hyprtk/configs/rofi/config-wallpaper.rasi -p "Wallpapers")

if [ "$selected" ]; then

    echo "Changing theme..."
    # Update wallpaper with pywal16
    wal -q -i "$HOME/Pictures/Wallpapers/$selected" 

    # Wait for 1 sec
    sleep 1

    # Read the selected wallpaper from pywal's JSON. Never `source` colors.sh:
    # the generated shell embeds the raw filename (a name with quotes/`;`/`$()`
    # would execute as shell).
    wallpaper="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("wallpaper",""))' "$HOME/.cache/wal/colors.json" 2>/dev/null)"

    newwall=$(basename "$wallpaper")

    # ----------------------------------------------------- 
    # Copy selected wallpaper into .cache folder
    # ----------------------------------------------------- 
    [ -f "$wallpaper" ] && cp "$wallpaper" ~/.cache/current-wallpaper.png

    ~/hyprtk/assets/papirus-icons/scripts/change-icons.sh

    # Send notification
    notify-send "Colors and Wallpaper updated" "with image $newwall"

    echo "Done."
fi

