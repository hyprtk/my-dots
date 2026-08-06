#!/bin/bash
# ── OneDrive ──────────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

rclone --vfs-cache-mode writes mount OneDrive: ~/OneDrive &
notify-send "OneDrive connected" "Microsoft OneDrive successfully mounted."
