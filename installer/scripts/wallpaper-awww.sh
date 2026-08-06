#!/bin/bash
# ── Wallpaper (awww) ─────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

# ----------------------------------------------------- 
# Select wallpaper
# ----------------------------------------------------- 
selected=$(ls -1 ~/Pictures/Wallpapers | grep "png" | rofi -dmenu -config ~/hyprtk/configs/rofi/config-wallpaper.rasi)

if [ "$selected" ]; then

    echo "Changing theme..."
    # ----------------------------------------------------- 
    # Update wallpaper with pywal16
    # ----------------------------------------------------- 
    wal -q -i ~/Pictures/Wallpapers/$selected 

    # ----------------------------------------------------- 
    # Get new theme
    # ----------------------------------------------------- 
    source "$HOME/.cache/wal/colors.sh"

    ~/hyprtk/configs/swaylock/update-swaylock.sh

    # ----------------------------------------------------- 
    # Copy selected wallpaper into .cache folder
    # ----------------------------------------------------- 
    cp $wallpaper ~/.cache/current-wallpaper.png   

    newwall=$(echo $wallpaper | sed "s|$HOME/Pictures/Wallpapers/||g")

    # ----------------------------------------------------- 
    # Set the new wallpaper
    # ----------------------------------------------------- 
    awww img $wallpaper \
        --transition-bezier .43,1.19,1,.4 \
        --transition-fps=60 \
        --transition-type="random" \
        --transition-duration=0.7 \
        --transition-pos "$( hyprctl cursorpos )"

    ~/hyprtk/configs/waybar/launch.sh

    ~/hyprtk/configs/papirus-icons/scripts/change-icons.sh

    # ----------------------------------------------------- 
    # Send notification
    # ----------------------------------------------------- 
    notify-send "Colors and Wallpaper updated" "with image $newwall"

    echo "Done."
fi
