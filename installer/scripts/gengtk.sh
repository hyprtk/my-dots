#!/bin/bash
#
#
#  
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------   

# Read colours from pywal's JSON. Never `source` colors.sh: the generated shell
# embeds the raw wallpaper filename and is injectable.
background="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("colors",{}).get("color0","#000000"))' "$HOME/.cache/wal/colors.json" 2>/dev/null)"
foreground="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("colors",{}).get("color14","#ffffff"))' "$HOME/.cache/wal/colors.json" 2>/dev/null)"
background=${background:1}
foreground=${foreground:1}

oomoxconf="$(mktemp)"
trap 'rm -f -- "$oomoxconf"' EXIT

cat << HEREDOC > "$oomoxconf"
NAME="autotheme"
BG=$background
FG=$foreground
TXT_BG=$background
TXT_FG=$foreground
MENU_BG=$background
MENU_FG=$foreground
SEL_BG=$foreground
SEL_FG=$background
BTN_BG=$background
BTN_FG=$foreground
HEREDOC

oomox-cli "$oomoxconf"
icon.sh "#$foreground"

sed -i 's/-/_/g' ~/.gtkrc-2.0
. ~/.gtkrc-2.0 2>&1
rm ~/.gtkrc-2.0

gtk_theme_name="oomox-$(basename "$oomoxconf")"
gtk_icon_theme_name=acyl
gtkvars=(theme-name icon-theme-name font-name cursor-theme-name cursor-theme-size toolbar-style toolbar-icon-size button-images menu-images enable-event-sounds enable-input-feedback-sounds xft-antialias xft-hinting xft-hintstyle xft-rgba)

for i in "${gtkvars[@]}"; do
    varname="gtk_${i//-/_}"
    value="${!varname:-}"
    echo "gtk-$i=\"$value\"" >> ~/.gtkrc-2.0
done

gtkrc-reload