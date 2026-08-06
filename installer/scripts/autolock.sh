#!/bin/bash
# ── Auto Lock ─────────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────
# NOTE: xautolock is X11-only. On Wayland/Hyprland, use hypridle instead.
# This script is kept for X11 session compatibility.

if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    pkill xautolock 2>/dev/null || true
    xautolock -time 10 -locker "swaylock -i ~/.cache/current_wallpaper.jpg" -notify 30 -notifier "notify-send 'Screen will be locked soon.' 'Locking screen in 30 seconds'"
else
    echo "This script requires X11. On Wayland, configure hypridle instead."
fi
