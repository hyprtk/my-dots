#!/bin/bash
# ── hyprtk-bar-gtk4 · E2E in-container driver ───────────────────────────────
# Runs inside the test image. Starts a headless sway (wlr-layer-shell capable),
# wires the fake hyprctl, then runs the suite (both GTK stacks + reporter).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# Give the bar a real session bus so NotificationController can own
# org.freedesktop.Notifications and the tray/SNI watchers can register.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$0" "$@"
fi

WORK=/work
E2E="$WORK/tools/e2e"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/xdg}"
export HYPRLAND_INSTANCE_SIGNATURE="e2e"
export E2E_REPORT_DIR="${E2E_REPORT_DIR:-$E2E/report}"
mkdir -p "$XDG_RUNTIME_DIR" "$E2E_REPORT_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# fake hyprctl first on PATH
install -m 0755 "$E2E/fake-hyprctl" /usr/local/bin/hyprctl

# dummy Hyprland socket2 path so HyprIPC can find something to connect to
mkdir -p "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE"
: > "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null || true

echo "== starting headless sway =="
sway -c "$E2E/sway-headless.conf" -d >/tmp/sway.log 2>&1 &
SWAY_PID=$!
cleanup() { kill "$SWAY_PID" 2>/dev/null; wait "$SWAY_PID" 2>/dev/null; }
trap cleanup EXIT

# wait for the compositor socket
for _ in $(seq 1 100); do
    sock=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -1 || true)
    if [ -n "$sock" ]; then
        export WAYLAND_DISPLAY="$(basename "$sock")"
        break
    fi
    sleep 0.1
done
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "!! sway did not come up; log follows" >&2
    sed -n '1,120p' /tmp/sway.log >&2
    exit 2
fi
echo "== sway up on $WAYLAND_DISPLAY =="

python "$E2E/run_e2e.py" "$@"
rc=$?
echo "== suite exit: $rc =="
exit "$rc"
