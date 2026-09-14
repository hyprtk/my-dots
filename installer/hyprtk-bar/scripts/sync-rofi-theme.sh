#!/bin/bash
# sync-rofi-theme.sh — link the rofi variant to match the current hyprtk-bar theme
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#
# The bar's ``theme.source`` selects the rofi variant:
#   pywal    -> hyprtk-pywal (the dynamic pywal variant; re-tints on wallpaper change)
#   imported -> the matching imported-theme variant (e.g. hyprtk-aero -> hyprtk-aero.rasi)
#   manual   -> hyprtk (default glass)
# Missing variants fall back to hyprtk.

bar_config="$HOME/.config/hyprtk-bar/config.json"
variant_dir="$SCRIPT_DIR/rofi/variants"
[ -d "$variant_dir" ] || variant_dir="$HOME/hyprtk/configs/rofi/variants"
symlink="$HOME/.config/rofi/variant.rasi"
[ -d "$(dirname "$symlink")" ] || symlink="$HOME/hyprtk/configs/rofi/variant.rasi"

theme="hyprtk"

if [ -f "$bar_config" ]; then
    # Pass the config path as argv[1] (not string-interpolated into the Python
    # source) so a home path with quotes can't break/inject the command.
    source=$(python3 - "$bar_config" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(d.get('theme', {}).get('source', ''))
PY
)
    theme_name=$(python3 - "$bar_config" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(d.get('theme', {}).get('theme_name', ''))
PY
)
    if [ "$source" = "pywal" ]; then
        theme="hyprtk-pywal"
    elif [ -n "$theme_name" ]; then
        theme="$theme_name"
    fi
fi

theme="${theme%-top}"
theme="${theme%-bottom}"

# The theme name reaches `ln -sf` below; allow only a safe identifier (no
# ../, no separators) so a hand-edited config can't redirect the rofi variant
# symlink outside the variants dir.
case "$theme" in
    ""|*[!A-Za-z0-9_.+-]*) theme="hyprtk" ;;
esac

if [ -f "$variant_dir/$theme.rasi" ]; then
    ln -sf "$variant_dir/$theme.rasi" "$symlink"
else
    ln -sf "$variant_dir/hyprtk.rasi" "$symlink"
fi
