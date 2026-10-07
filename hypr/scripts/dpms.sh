#!/bin/bash
# ── dpms.sh — log a DPMS transition, then dispatch it ───────────────────────
# The idle monitor-off path (hypridle/swayidle → hyprctl dpms off/on, see
# hypr/hypridle.conf and installer/scripts/lockscreentime.sh) is where the
# compositor has been seen to
# freeze on wake. Timestamp every transition to a persistent log so a freeze
# can be correlated with the exact DPMS event that preceded it.
#
# Usage: dpms.sh on|off|toggle
# ─────────────────────────────────────────────────────────────────────────────

state="${1:-}"
before=$(hyprctl -j monitors 2>/dev/null | grep -o '"dpmsStatus": *[a-z]*' | head -n1 | tr -d ' ')
case "$state" in
    on)     enable="true" ;;
    off)    enable="false" ;;
    toggle) [ "${before##*:}" = "true" ] && enable="false" || enable="true" ;;
    *)      echo "usage: dpms.sh on|off|toggle" >&2; exit 2 ;;
esac

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprtk"
LOG="$STATE_DIR/dpms.log"
mkdir -p "$STATE_DIR"
out=$(timeout 8 hyprctl dispatch "hl.dsp.dpms({ enable = $enable })" 2>&1)
rc=$?
after=$(hyprctl -j monitors 2>/dev/null | grep -o '"dpmsStatus":[a-z]*' | head -n1)

printf '%s dpms %s rc=%s before=%s after=%s result=%s\n' \
    "$(date -Is)" "$state" "$rc" "${before:-?}" "${after:-?}" "$out" >> "$LOG"
exit "$rc"
