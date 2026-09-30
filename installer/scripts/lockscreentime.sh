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
    # DPMS goes through hypr/scripts/dpms.sh, which timestamps each transition —
    # the idle monitor-off/wake path is where the compositor has been seen to
    # freeze (see hypr-watchdog.sh).
    swayidle -w timeout $timeswaylock "$HOME/.config/hypr/scripts/lock.sh -f" timeout $timeoff "$HOME/.config/hypr/scripts/dpms.sh off" resume "$HOME/.config/hypr/scripts/dpms.sh on"
else
    echo "swayidle not installed."
fi;
