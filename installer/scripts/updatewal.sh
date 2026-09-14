#!/bin/bash
#
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

echo "Changing theme..."

# ----------------------------------------------------- 
# Update Wallpaper with pywal
# ----------------------------------------------------- 
wal -q -i ~/Pictures/Wallpapers/ 

# ----------------------------------------------------- 
# Wait for 1 sec
# ----------------------------------------------------- 
sleep 1

# ----------------------------------------------------- 
# Get new theme
# ----------------------------------------------------- 
source "$HOME/.cache/wal/colors.sh"
newwall=$(basename "$wallpaper")

# ----------------------------------------------------- 
# Copy selected wallpaper into .cache folder
# ----------------------------------------------------- 
cp "$wallpaper" ~/.cache/current-wallpaper.png

~/hyprtk/assets/papirus-icons/scripts/change-icons.sh

# ----------------------------------------------------- 
# Send notification
# ----------------------------------------------------- 
notify-send "Colors and Wallpaper updated" "with image $newwall"

echo "Done."
