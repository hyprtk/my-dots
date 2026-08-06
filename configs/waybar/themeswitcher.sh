#!/bin/bash
# ── Theme Switcher ────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

# ----------------------------------------------------- 
# Default theme folder
# ----------------------------------------------------- 
themes_path="$HOME/hyprtk/configs/waybar/themes"

# ----------------------------------------------------- 
# Initialize arrays
# ----------------------------------------------------- 
listThemes=()
listNames=""

# ----------------------------------------------------- 
# Read theme folder and sort by base name, then bottom before top
# ----------------------------------------------------- 
sorted=$(find "$themes_path" -maxdepth 2 -type d | while read -r d; do
    name=$(basename "$d")
    key=$(echo "$name" | sed 's/-top$//;s/-bottom$//')
    pos=1
    case "$name" in *-bottom) pos=0;; esac
    printf '%s\t%d\t%s\n' "$key" "$pos" "$d"
done | sort -t$'\t' -k1,1 -k2,2n | cut -f3)

for value in $sorted
do
    if [ ! "$value" = "$themes_path" ]; then
        if [ "$(find "$value" -maxdepth 1 -type d | wc -l)" = 1 ]; then
            result=$(echo "$value" | sed "s#$HOME/hyprtk/configs/waybar/themes/#/#g")
            IFS='/' read -ra arrThemes <<< "$result"
            listThemes[${#listThemes[@]}]="/${arrThemes[1]};$result"
            if [ -f "$themes_path$result/config.sh" ]; then
                source "$themes_path$result/config.sh"
                listNames+="$theme_name\n"
            else
                listNames+="/${arrThemes[1]};$result\n"
            fi
        fi
    fi
done

# ----------------------------------------------------- 
# Show rofi dialog
# ----------------------------------------------------- 
listNames=${listNames::-2}
choice=$(echo -e "$listNames" | rofi -dmenu -config "$HOME/hyprtk/configs/rofi/config-wallpaper.rasi" -no-show-icons -width 30 -p "Themes" -format i) 

# ----------------------------------------------------- 
# Set new theme by writing the theme information to ~/.cache/.themestyle.sh
# ----------------------------------------------------- 
if [ "$choice" ]; then
    echo "${listThemes[$choice]}" > ~/.cache/.themestyle.sh
    "$HOME/hyprtk/configs/rofi/scripts/sync-rofi-theme.sh"
    "$HOME/hyprtk/configs/waybar/launch.sh"
fi
