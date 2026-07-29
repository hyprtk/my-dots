#!/bin/sh
#  ████████   ██                      ██
# ██░░░░░░   ░██                     ░██
#░██        ██████  ██████   ██████ ██████
#░█████████░░░██░  ░░░░░░██ ░░██░░█░░░██░
#░░░░░░░░██  ░██    ███████  ░██ ░   ░██
#       ░██  ░██   ██░░░░██  ░██     ░██
# ████████   ░░██ ░░████████░███     ░░██
#░░░░░░░░     ░░   ░░░░░░░░ ░░░       ░░
# ██       ██                    ██
#░██      ░██            ██   ██░██
#░██   █  ░██  ██████   ░░██ ██ ░██       ██████   ██████
#░██  ███ ░██ ░░░░░░██   ░░███  ░██████  ░░░░░░██ ░░██░░█
#░██ ██░██░██  ███████    ░██   ░██░░░██  ███████  ░██ ░
#░████ ░░████ ██░░░░██    ██    ░██  ░██ ██░░░░██  ░██
#░██░   ░░░██░░████████  ██     ░██████ ░░████████░███
#░░       ░░  ░░░░░░░░  ░░      ░░░░░    ░░░░░░░░ ░░░
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

# ----------------------------------------------------- 
# Quit all running waybar instances
# ----------------------------------------------------- 
killall waybar

# ----------------------------------------------------- 
# Default theme: /THEMEFOLDER;/VARIATION
# ----------------------------------------------------- 
themestyle="/hyprtk;/hyprtk"

# ----------------------------------------------------- 
# Get current theme information from .cache/.themestyle.sh
# ----------------------------------------------------- 
if [ -f ~/.cache/.themestyle.sh ]; then
    themestyle=$(cat ~/.cache/.themestyle.sh)
fi

IFS=';' read -ra arrThemes <<< "$themestyle"

# Validate theme data; fall back to hyprtk if broken
if [ ${#arrThemes[@]} -lt 2 ] || [ ! -f ~/hyprtk/waybar/themes${arrThemes[1]}/style.css ]; then
    themestyle="/hyprtk;/hyprtk"
    IFS=';' read -ra arrThemes <<< "$themestyle"
fi

echo "${arrThemes[0]}"

# ----------------------------------------------------- 
# Sync rofi variant to match current waybar theme
# ----------------------------------------------------- 
~/hyprtk/rofi/scripts/sync-rofi-theme.sh

# ----------------------------------------------------- 
# Loading the configuration and style file
# ----------------------------------------------------- 
waybar -c ~/hyprtk/waybar/themes${arrThemes[0]}/config -s ~/hyprtk/waybar/themes${arrThemes[1]}/style.css &