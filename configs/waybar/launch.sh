#!/bin/bash
# ── Waybar Launch ─────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

# ----------------------------------------------------- 
# Quit all running waybar instances
# ----------------------------------------------------- 
killall waybar

# ----------------------------------------------------- 
# Default theme: /THEMEFOLDER;/VARIATION
# ----------------------------------------------------- 
themestyle="/hyprtk-top;/hyprtk-top"

# ----------------------------------------------------- 
# Get current theme information from .cache/.themestyle.sh
# ----------------------------------------------------- 
if [ -f ~/.cache/.themestyle.sh ]; then
    themestyle=$(cat ~/.cache/.themestyle.sh)
fi

IFS=';' read -ra arrThemes <<< "$themestyle"

# Validate theme data; fall back to hyprtk-top if broken
if [ ${#arrThemes[@]} -lt 2 ] || [ ! -f ~/hyprtk/configs/waybar/themes${arrThemes[1]}/style.css ]; then
    themestyle="/hyprtk-top;/hyprtk-top"
    IFS=';' read -ra arrThemes <<< "$themestyle"
fi

echo "${arrThemes[0]}"

# ----------------------------------------------------- 
# Sync rofi variant to match current waybar theme
# ----------------------------------------------------- 
~/hyprtk/configs/rofi/scripts/sync-rofi-theme.sh

# ----------------------------------------------------- 
# Generate aero colors if needed (pywal → waybar + rofi)
# ----------------------------------------------------- 
if echo "${arrThemes[1]}" | grep -q "aero"; then
    bash ~/hyprtk/hypr/scripts/generate-aero-colors.sh 2>/dev/null
fi

# ----------------------------------------------------- 
# Loading the configuration and style file
# ----------------------------------------------------- 
waybar -c ~/hyprtk/configs/waybar/themes${arrThemes[0]}/config -s ~/hyprtk/configs/waybar/themes${arrThemes[1]}/style.css &