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
themestyle="/Top-Blur;/Top-Blur/colored"

# ----------------------------------------------------- 
# Get current theme information from .cache/.themestyle.sh
# ----------------------------------------------------- 
if [ -f ~/.cache/.themestyle.sh ]; then
    themestyle=$(cat ~/.cache/.themestyle.sh)
else
    touch ~/.cache/.themestyle.sh
    echo "$themestyle" > ~/.cache/.themestyle.sh
fi

IFS=';' read -ra arrThemes <<< "$themestyle"
echo ${arrThemes[0]}

if [ ! -f ~/hyprtk/common/waybar/themes${arrThemes[1]}/style.css ]; then
    themestyle="/Top;/Top/light"
fi

# ----------------------------------------------------- 
# Loading the configuration and style file based on the username
# ----------------------------------------------------- 
if [[ $USER = "hyprtk" ]]
then
    waybar -c ~/hyprtk/common/waybar/themes${arrThemes[0]}/myconfig -s ~/hyprtk/common/waybar/themes${arrThemes[1]}/style.css &
else
    waybar -c ~/hyprtk/common/waybar/themes${arrThemes[0]}/config -s ~/hyprtk/common/waybar/themes${arrThemes[1]}/style.css &
fi