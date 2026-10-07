#!/bin/bash
# ── lock.sh — lock the screen: single-instance, restart-on-death ────────────
# Hyprland keeps the session LOCKED when the lock client exits without
# unlocking (a crash, an OOM-kill, a DRM hotplug, …) and, with the default
# misc:allow_session_lock_restore = false, refuses every replacement — the
# session then cannot be unlocked at all and needs a reboot. The dotfiles enable
# allow_session_lock_restore (hypr/misc.lua), so a fresh instance can take the
# existing lock over; this wrapper exploits that by restarting the locker after
# an abnormal exit. A normal unlock exits 0 and ends the loop.
#
# Two hardening measures on top of that (see the 2026-10-01 lock-death report):
#
#   1. Single instance. This script holds an exclusive flock for as long as the
#      session is locked. A second invocation — the idle timer re-firing, the
#      `lock` alias, the logout menu, or a hotplug-triggered relock — exits
#      immediately instead of stacking another locker. Previously every
#      request spawned a fresh supervisor, so instances accumulated (8 locker
#      processes seen) and unlocking one no longer released the session.
#
#   2. Settle before (re)starting. A restart waits until Hyprland reports at
#      least one monitor, so it does not race the DRM re-modeset that follows a
#      monitor hotplug — the DP-1 flap on the DPMS-wake path (Samsung C49J89x)
#      that killed the previous lock client.
#
# Every phase is timestamped to $XDG_STATE_HOME/hyprtk/lock.log; hypr-watchdog.sh
# reads the same flock to detect "locked but no client alive".
#
# Usage: lock.sh [locker args...]
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprtk"
LOG="$STATE_DIR/lock.log"
mkdir -p "$STATE_DIR" 2>/dev/null

log() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG" 2>/dev/null; }

# 1. Single instance. The flock is held for the whole locked period and is
#    released automatically when this process dies; flock is advisory so a
#    stale file is harmless.
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/hyprtk-session.lock"
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCKFILE" || exit 1
    if ! flock -n 9; then
        log "duplicate lock request ignored (already locked)"
        exit 0
    fi
fi

# 2. Wait (briefly) for an output to exist before starting the lockscreen, so a
#    restart after a hotplug does not race the re-modeset.
outputs_ready() {
    [ "$(timeout 2 hyprctl -j monitors 2>/dev/null | grep -c '"name"')" -gt 0 ] 2>/dev/null
}

settle() {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        outputs_ready && return 0
        sleep 0.2
    done
    return 1
}

# Prefer hyprlock (Hyprland's GPU-accelerated locker); fall back to swaylock
# while the hyprlock package is not present on every target yet. hyprlock exits
# WITHOUT locking when its config is missing (leaving the session unlocked), so
# only pick it when hyprlock.conf is present — otherwise use swaylock. Both use
# ext-session-lock, so the crash-restart logic below is identical either way.
if command -v hyprlock >/dev/null 2>&1 && [ -f "$HOME/.config/hypr/hyprlock.conf" ]; then
    LOCKER=hyprlock
elif command -v swaylock >/dev/null 2>&1; then
    LOCKER=swaylock
else
    log "no usable lockscreen client (hyprlock+config, or swaylock)"
    exit 1
fi

tries=0
while :; do
    settle || log "no monitor reported yet; starting lockscreen anyway"
    "$LOCKER" "$@"
    rc=$?
    # 0 = unlocked normally; anything else is a crash/abnormal exit.
    if [ "$rc" -eq 0 ]; then
        log "unlocked normally"
        break
    fi
    tries=$((tries + 1))
    log "lockscreen exited rc=$rc; restarting (attempt $tries)"
    # Fast retry at first; back off so a persistent failure does not spin, but
    # keep trying — an unwrapped lock leaves the session stuck on the crash
    # screen.
    if [ "$tries" -le 10 ]; then
        sleep 1
    else
        sleep 4
    fi
done
