#!/bin/bash
#
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Bundled wal (vendored pywal16): prefer $HYPRTK_WAL (set by hyprtk-bar), then
# the launcher beside this install, then PATH.
WAL="${HYPRTK_WAL:-}"
if [ -z "$WAL" ] && [ -x "$SCRIPT_DIR/../venv/bin/wal" ]; then
    WAL="$SCRIPT_DIR/../venv/bin/wal"
fi
WAL="${WAL:-wal}"

# ----------------------------------------------------- 
# Select random wallpaper and create color scheme
# ----------------------------------------------------- 
"$WAL" -q -i ~/Pictures/Wallpapers/ 

# ----------------------------------------------------- 
# Load current pywal16 color scheme
# ----------------------------------------------------- 
source "$HOME/.cache/wal/colors.sh"

# ----------------------------------------------------- 
# Copy selected wallpaper into .cache folder
# ----------------------------------------------------- 
cp "$wallpaper" ~/.cache/current-wallpaper.png

# ----------------------------------------------------- 
# get wallpaper iamge name
# ----------------------------------------------------- 
newwall=$(basename "$wallpaper")

# ----------------------------------------------------- 
# Set the new wallpaper (ensure the daemon is running first)
# ----------------------------------------------------- 
if command -v awww >/dev/null 2>&1; then
    pgrep -x awww-daemon >/dev/null 2>&1 || { setsid awww-daemon >/dev/null 2>&1 & sleep 0.4; }
    awww img "$wallpaper" \
        --transition-bezier .43,1.19,1,.4 \
        --transition-fps=60 \
        --transition-type="random" \
        --transition-duration=0.7 \
        --transition-pos "$( hyprctl cursorpos )"
elif command -v swww >/dev/null 2>&1; then
    pgrep -x swww-daemon >/dev/null 2>&1 || { setsid swww-daemon >/dev/null 2>&1 & sleep 0.4; }
    swww img "$wallpaper" \
        --transition-bezier .43,1.19,1,.4 \
        --transition-fps=60 \
        --transition-type="random" \
        --transition-duration=0.7 \
        --transition-pos "$( hyprctl cursorpos )"
fi

"$SCRIPT_DIR/change-icons.sh"

# ----------------------------------------------------- 
# Send notification
# ----------------------------------------------------- 
notify-send "Colors and Wallpaper updated" "with image $newwall"

echo "DONE!"
