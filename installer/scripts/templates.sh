#!/bin/bash
# ── Templates ─────────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

# Select text file
selected=$(ls -1 ~/private/templates | rofi -dmenu -p "Select the template")

if [ "$selected" ]; then
    # Add content to clipboard (wl-copy for Wayland, xclip fallback for X11)
    if command -v wl-copy &>/dev/null; then
        cat ~/private/templates/"$selected" | wl-copy
    elif command -v xclip &>/dev/null; then
        xclip -sel clip ~/private/templates/"$selected"
    else
        echo "No clipboard tool found (wl-copy or xclip)"
    fi
fi
