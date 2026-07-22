#!/usr/bin/env bash
WAL_JSON="$HOME/.cache/wal/colors.json"

if [ -f "$WAL_JSON" ]; then
    ICON_COLOR=$(grep -o '"color5": *"#[^"]*"' "$WAL_JSON" | grep -o '#[^"]*')
    TEXT_COLOR=$(grep -o '"foreground": *"#[^"]*"' "$WAL_JSON" | grep -o '#[^"]*')
    echo "<span foreground='${ICON_COLOR}'></span> <span foreground='${TEXT_COLOR}'>Home</span>"
else
    echo " Home"
fi
