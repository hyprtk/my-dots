#!/bin/bash
# ── hypr-watchdog.sh — capture the next compositor stall ────────────────────
# Diagnoses the intermittent "frozen while idle/locked" hang (aquamarine
# DRM page-flip stall on the DPMS-off → wake path; see CHANGELOG/handoff).
#
# Hyprland's own log lives in $XDG_RUNTIME_DIR/hypr/<sig>/hyprland.log, which
# is tmpfs and wiped on reboot — so a freeze leaves no evidence. This daemon:
#
#   1. Mirrors that runtime log (and the socket2 monitor/DPMS events) into a
#      persistent $XDG_STATE_HOME/hyprtk/ directory, so they survive a reboot.
#   2. Heartbeats the compositor every few seconds. Consecutive timeouts while
#      the Hyprland process is still alive = a hang (not a crash). On the Nth
#      miss it writes a timestamped snapshot: kernel + user journals, the
#      mirrored log, DRM connector state, process state and hyprctl output.
#   3. Watches the session lock. lock.sh holds $XDG_RUNTIME_DIR/hyprtk-session.lock
#      for as long as the session is locked; if that lock is held but no
#      lockscreen process is alive, the client died (the DPMS-wake DP-1 hotplug
#      flap that leaves the "lockscreen app died" screen). Snapshot it too, since
#      the compositor itself stays alive and the hang heartbeat never fires.
#
# It runs as a plain child process, so it keeps working while the compositor's
# event loop is blocked. No root, no extra packages required.
#
# Usage: hypr-watchdog.sh &   (from hypr/autostart.lua)
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprtk"
INTERVAL=3          # seconds between heartbeats
TIMEOUT=5           # hyprctl timeout (hang if it exceeds this)
FAIL_THRESHOLD=3    # consecutive misses that count as a stall
KEEP_DUMPS=5        # snapshots to retain
MAX_MIRROR=$((32 * 1024 * 1024))

mkdir -p "$STATE_DIR" || exit 1
chmod 700 "$STATE_DIR" 2>/dev/null

# Single instance — a second copy would double-append the mirror.
if command -v flock >/dev/null 2>&1; then
    exec 9>"$STATE_DIR/watchdog.lock" || exit 1
    flock -n 9 || exit 0
fi

# Kill the mirror/event children when this daemon exits.
trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT EXIT

# Resolve the running compositor's runtime directory + signature.
sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$sig" ]; then
    sig=$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
fi
runtime="$XDG_RUNTIME_DIR/hypr/$sig"
[ -d "$runtime" ] || { echo "hypr-watchdog: no runtime dir ($runtime)" >&2; exit 1; }
RUNTIME_LOG_SRC="$runtime/hyprland.log"

MIRROR="$STATE_DIR/hyprland-last.log"
EVENT_LOG="$STATE_DIR/events-last.log"
DPMS_LOG="$STATE_DIR/dpms.log"
LOCK_LOG="$STATE_DIR/lock.log"
# lock.sh holds this flock for the whole locked period (see lock.sh).
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/hyprtk-session.lock"

# Keep the persistent mirror bounded across sessions.
if [ -f "$MIRROR" ] && [ "$(stat -c%s "$MIRROR" 2>/dev/null || echo 0)" -gt "$MAX_MIRROR" ]; then
    tail -c $((MAX_MIRROR / 4)) "$MIRROR" > "$MIRROR.tmp" && mv "$MIRROR.tmp" "$MIRROR"
fi
printf '\n===== watchdog start %s (sig %s) =====\n' "$(date -Is)" "$sig" >> "$MIRROR"

hypr_pid() { pgrep -x Hyprland 2>/dev/null | head -n1; }

# Is the session locked? lock.sh holds an exclusive flock on LOCKFILE for the
# whole locked period and releases it only on a normal unlock, so a failed
# non-blocking flock at that path means "locked".
lock_held() {
    command -v flock >/dev/null 2>&1 || return 1
    [ -e "$LOCKFILE" ] || return 1
    flock -n "$LOCKFILE" true 2>/dev/null && return 1 || return 0
}

# Is any lockscreen client alive? (hyprlock is the hyprtk default; swaylock is
# accepted for the fallback path.)
lock_client_alive() {
    pgrep -x hyprlock >/dev/null 2>&1 || pgrep -x swaylock >/dev/null 2>&1
}

# 1. Mirror Hyprland's runtime log into persistent storage.
tail -n +1 -F "$runtime/hyprland.log" >> "$MIRROR" 2>/dev/null &

# 2. Persist monitor/DPMS-relevant socket2 events.
#    The socket must be connect()ed (nc -U); bash redirection open()s it and
#    fails with ENXIO, so we require netcat and skip the stream if absent.
event_sock="$runtime/.socket2.sock"
if [ -S "$event_sock" ] && command -v nc >/dev/null 2>&1; then
    (
        nc -U "$event_sock" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                monitor*|dpms*|configreloaded*|activelayout*)
                    printf '%s %s\n' "$(date -Is)" "$line" >> "$EVENT_LOG" ;;
            esac
        done
    ) &
fi

snapshot() {
    local reason="$1" pid="$2"
    local dir="$STATE_DIR/freeze-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir" || return
    {
        echo "reason:   $reason"
        echo "time:     $(date -Is)"
        echo "uptime:   $(uptime)"
        echo "hypr pid: $pid"
        echo "sig:      $sig"
        echo "locked:   $(lock_held && echo yes || echo no)"
        echo "lockpids: $({ pgrep -x hyprlock; pgrep -x swaylock; } 2>/dev/null | tr '\n' ' ')"
    } > "$dir/summary.txt"

    [ -n "$pid" ] && {
        grep -E '^(State|VmRSS|Threads)' "/proc/$pid/status" >> "$dir/summary.txt" 2>/dev/null
        echo "wchan: $(cat "/proc/$pid/wchan" 2>/dev/null)" >> "$dir/summary.txt"
        echo "stat:  $(cat "/proc/$pid/stat" 2>/dev/null)" >> "$dir/summary.txt"
    }

    journalctl -k -b --no-pager > "$dir/kernel.log" 2>&1
    journalctl --user -b -n 4000 --no-pager > "$dir/user.log" 2>&1
    cp -f "$RUNTIME_LOG_SRC" "$dir/hyprland.log" 2>/dev/null
    tail -n 500 "$EVENT_LOG" > "$dir/events.log" 2>/dev/null
    tail -n 200 "$DPMS_LOG" > "$dir/dpms.log" 2>/dev/null
    tail -n 200 "$LOCK_LOG" > "$dir/lock.log" 2>/dev/null

    {   for c in /sys/class/drm/card*/card*/*; do
            case "${c##*/}" in status|enabled|dpms|modes) [ -r "$c" ] && echo "${c}: $(cat "$c")";; esac
        done
        for g in /sys/class/drm/card*/device/gpu_busy_percent \
                 /sys/class/drm/card*/device/mem_info_vram_used; do
            [ -r "$g" ] && echo "${g}: $(cat "$g")"
        done
    } > "$dir/drm.txt" 2>&1

    ps -eo pid,ppid,stat,pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | head -n 40 > "$dir/ps.txt"
    timeout "$TIMEOUT" hyprctl -j monitors > "$dir/hyprctl-monitors.json" 2>&1
    timeout "$TIMEOUT" hyprctl -j clients  > "$dir/hyprctl-clients.json"  2>&1
    echo "hyprctl exit: $?" >> "$dir/summary.txt"

    # Trim to the newest KEEP_DUMPS snapshots.
    ls -1dt "$STATE_DIR"/freeze-* 2>/dev/null | tail -n +$((KEEP_DUMPS + 1)) | xargs -r rm -rf
    echo "hypr-watchdog: captured $reason -> $dir" >&2
}

fails=0
lock_fails=0
while :; do
    sleep "$INTERVAL"
    pid=$(hypr_pid)
    if [ -z "$pid" ]; then
        [ "$fails" -ge 0 ] && snapshot "compositor exited" ""
        exit 0
    fi
    if timeout "$TIMEOUT" hyprctl -j activeworkspace >/dev/null 2>&1; then
        fails=0
        # Compositor responsive: the lock client must still be alive. The
        # threshold debounces the brief gap while lock.sh restarts the locker
        # (1s backoff / settle), so only a real death is snapshotted.
        if lock_held && ! lock_client_alive; then
            lock_fails=$((lock_fails + 1))
            if [ "$lock_fails" -eq "$FAIL_THRESHOLD" ]; then
                snapshot "lockscreen client died while session locked" "$pid"
            fi
        else
            lock_fails=0
        fi
    else
        fails=$((fails + 1))
        if [ "$fails" -eq "$FAIL_THRESHOLD" ]; then
            snapshot "compositor unresponsive (${fails}× ${TIMEOUT}s timeout)" "$pid"
        fi
    fi
done
