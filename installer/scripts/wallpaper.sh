#!/bin/bash
#
# ██       ██            ██  ██
#░██      ░██           ░██ ░██ ██████            ██████
#░██   █  ░██  ██████   ░██ ░██░██░░░██  ██████  ░██░░░██  █████  ██████
#░██  ███ ░██ ░░░░░░██  ░██ ░██░██  ░██ ░░░░░░██ ░██  ░██ ██░░░██░░██░░█
#░██ ██░██░██  ███████  ░██ ░██░██████   ███████ ░██████ ░███████ ░██ ░
#░████ ░░████ ██░░░░██  ░██ ░██░██░░░   ██░░░░██ ░██░░░  ░██░░░░  ░██
#░██░   ░░░██░░████████ ███ ███░██     ░░████████░██     ░░██████░███
#░░       ░░  ░░░░░░░░ ░░░ ░░░ ░░       ░░░░░░░░ ░░       ░░░░░░ ░░░ 
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

# Select wallpaper
selected=$(ls -1 ~/Pictures/Wallpapers | grep "png" | rofi -dmenu -config ~/hyprtk/configs/rofi/config-wallpaper.rasi -p "Wallpapers")

if [ "$selected" ]; then

    echo "Changing theme..."
    # Update wallpaper with pywal16
    wal -q -i ~/Pictures/Wallpapers/$selected 

    # Wait for 1 sec
    sleep 1

    # Get new theme
    source "$HOME/.cache/wal/colors.sh"

    ~/hyprtk/configs/swaylock/update-swaylock.sh

    newwall=$(echo $wallpaper | sed "s|$HOME/Pictures/Wallpapers/||g")

    # ----------------------------------------------------- 
    # Copy selected wallpaper into .cache folder
    # ----------------------------------------------------- 
    cp $wallpaper ~/.cache/current-wallpaper.png

    ~/hyprtk/configs/papirus-icons/scripts/change-icons.sh

    # Send notification
    notify-send "Colors and Wallpaper updated" "with image $newwall"

    echo "Done."
fi

