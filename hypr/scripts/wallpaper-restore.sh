#!/usr/bin/env bash
#
# ─────────────────────────────────────────────────────────────────
#   HYPRTK · Wallpaper Restore
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────
# -----------------------------------------------------
# Restore last wallpaper
# -----------------------------------------------------
# Runs on startup — restores last wallpaper and pywal colors

WALLPAPER_CACHE="$HOME/.cache/wal/wal"
FALLBACK="$HOME/hyprtk/default.png"

sleep 1

WALLPAPER=$(cat "$WALLPAPER_CACHE" 2>/dev/null)
[ -f "$WALLPAPER" ] || WALLPAPER="$FALLBACK"
[ -f "$WALLPAPER" ] || exit 1

awww img "$WALLPAPER" --transition-type fade --transition-duration 2 --transition-fps 60

wal -i "$WALLPAPER" -n -q

[ -f ~/.cache/wal/colors-wofi.css ]      && cp ~/.cache/wal/colors-wofi.css    ~/.config/wofi/style.css
[ -f ~/.cache/wal/wob.ini ]              && cp ~/.cache/wal/wob.ini             ~/.config/wob/wob.ini
[ -f ~/.cache/wal/hyprland-colors.conf ] && cp ~/.cache/wal/hyprland-colors.conf ~/.config/hypr/hyprland-colors.conf

~/hyprtk/assets/papirus-icons/scripts/change-icons.sh
