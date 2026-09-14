#!/bin/bash
# Toggle the in-bar arc menu overlay by signalling the running hyprtk-bar.
# Hyprland keybindings can't talk to the bar directly, so the binding points
# here: read the bar's PID from its flock lock file and send SIGUSR2 (which
# the bar's entry point maps to arc-menu toggle).
set -uo pipefail

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pid_file="$runtime/hyprtk-bar.lock"

if [ -r "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        kill -USR2 "$pid" 2>/dev/null
    fi
fi
exit 0