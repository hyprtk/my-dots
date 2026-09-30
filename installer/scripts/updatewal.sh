#!/bin/bash
#
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

echo "Changing theme..."

# ----------------------------------------------------- 
# Update Wallpaper with pywal
# ----------------------------------------------------- 
wal -q -i "$HOME/Pictures/Wallpapers/"

# ----------------------------------------------------- 
# Wait for 1 sec
# ----------------------------------------------------- 
sleep 1

# ----------------------------------------------------- 
# Read the selected wallpaper from pywal's JSON (never `source` colors.sh:
# the generated shell embeds the raw filename and is injectable).
# ----------------------------------------------------- 
wallpaper="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("wallpaper",""))' "$HOME/.cache/wal/colors.json" 2>/dev/null)"
newwall=$(basename "$wallpaper")

# ----------------------------------------------------- 
# Copy selected wallpaper into .cache folder
# ----------------------------------------------------- 
[ -f "$wallpaper" ] && cp "$wallpaper" ~/.cache/current-wallpaper.png

~/hyprtk/assets/papirus-icons/scripts/change-icons.sh

# ----------------------------------------------------- 
# Send notification
# ----------------------------------------------------- 
notify-send "Colors and Wallpaper updated" "with image $newwall"

echo "Done."
