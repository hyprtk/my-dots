#!/bin/bash
# Toggle the in-bar clipboard history dialogue by signalling the running
# hyprtk-bar. Hyprland keybindings can't talk to the bar directly, so the
# binding points here: read the bar's PID from its flock lock file and send
# SIGHUP (which the bar's entry point maps to clipboard-dialogue toggle).
set -uo pipefail

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
pid_file="$runtime/hyprtk-bar.lock"

if [ -r "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        kill -HUP "$pid" 2>/dev/null
    fi
fi
exit 0
