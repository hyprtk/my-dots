#!/bin/sh
#
#  
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

timeswaylock=600
timeoff=660

if [ -f "/usr/bin/swayidle" ]; then
    echo "swayidle is installed."
    # Lock via hypr/scripts/lock.sh (restarts swaylock after the aquamarine
    # DRM page-flip crash) instead of raw swaylock, so an idle lock recovers.
    swayidle -w timeout $timeswaylock "$HOME/.config/hypr/scripts/lock.sh -f" timeout $timeoff "hyprctl dispatch 'hl.dsp.dpms({ enable = false })'" resume "hyprctl dispatch 'hl.dsp.dpms({ enable = true })'"
else
    echo "swayidle not installed."
fi;
