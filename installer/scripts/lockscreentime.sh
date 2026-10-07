#!/bin/sh
#
# lockscreentime.sh — idle-daemon FALLBACK (swayidle).
#
# hypridle is now the primary idle daemon: it is started from hypr/autostart.lua
# and configured by hypr/hypridle.conf. This script is kept only as a fallback
# for targets that do not package hypridle yet (autostart runs it only when
# `hypridle` fails or is absent). It runs the old swayidle timers, locking
# through hypr/scripts/lock.sh (single-instance, restart-on-death) and toggling
# the display through hypr/scripts/dpms.sh — the same paths hypridle uses.
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------

timeswaylock=600
timeoff=660

if command -v swayidle >/dev/null 2>&1; then
    echo "lockscreentime: using swayidle fallback (hypridle unavailable)."
    swayidle -w \
        timeout $timeswaylock "$HOME/.config/hypr/scripts/lock.sh" \
        timeout $timeoff "$HOME/.config/hypr/scripts/dpms.sh off" \
        resume "$HOME/.config/hypr/scripts/dpms.sh on"
else
    echo "lockscreentime: neither hypridle nor swayidle is installed." >&2
fi
