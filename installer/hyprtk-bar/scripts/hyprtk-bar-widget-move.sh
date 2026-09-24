#!/bin/bash
# Start/stop a desktop-widget move by writing to the bar's control FIFO.
#
# Hyprland binds Super + Shift + left mouse (press -> "start", release -> "stop") to
# this script. GTK never sees the Super modifier on a keyboard_mode=none
# layer surface, so the move gesture is driven from the compositor: the bar
# reads the FIFO, then polls the cursor and moves the widget under it.
set -uo pipefail

action="${1:-start}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
fifo="$runtime/hyprtk-bar-widget-move.fifo"

if [ -p "$fifo" ]; then
    printf '%s\n' "$action" > "$fifo" 2>/dev/null || true
fi
exit 0
