#!/bin/sh
#
#  
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

timeswaylock=600
timeoff=660

if [ -f "/usr/bin/swayidle" ]; then
    echo "swayidle is installed."
    swayidle -w timeout $timeswaylock 'swaylock -f' timeout $timeoff "hyprctl dispatch 'hl.dsp.dpms({ enable = false })'" resume "hyprctl dispatch 'hl.dsp.dpms({ enable = true })'"
else
    echo "swayidle not installed."
fi;
