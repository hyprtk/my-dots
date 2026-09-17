#!/bin/bash
# ── matuwall-toggle.sh — toggle the Matuwall wallpaper picker ──────────────
# Matuwall is now a C11 + meson, one-shot layer-shell client: there is no venv,
# no GTK4/gtk4-layer-shell LD_PRELOAD and no `--toggle` flag (the old Python app
# had all three). Launch it on demand and kill it to hide the picker.
# ─────────────────────────────────────────────────────────────────────────────

if pgrep -x matuwall >/dev/null 2>&1; then
    pkill -x matuwall
else
    nohup matuwall >/dev/null 2>&1 &
fi
