#!/bin/bash
# ── lock.sh — lock the screen, restarting the lockscreen if it dies ─────────
# Hyprland keeps the session LOCKED when the lock client exits without
# unlocking (a crash, an OOM-kill, …) and, with the default
# misc:allow_session_lock_restore = false, refuses every replacement — the
# session then cannot be unlocked at all and needs a reboot. The dotfiles enable
# allow_session_lock_restore (hypr/misc.lua), so a fresh instance can take the
# existing lock over; this wrapper exploits that by restarting swaylock after an
# abnormal exit. A normal unlock exits 0 and ends the loop.
#
# Usage: lock.sh [swaylock args...]
# ─────────────────────────────────────────────────────────────────────────────

while :; do
    swaylock "$@"
    rc=$?
    # 0 = unlocked normally; anything else is a crash/abnormal exit.
    [ "$rc" -eq 0 ] && break
    sleep 1
done
