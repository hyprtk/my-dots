#!/bin/sh
#
# Icon Color Select
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 


SCRIPT_DIR="$HOME/hyprtk/papirus-icons"
selected=$(ls "$SCRIPT_DIR" | grep "sh" | rofi -dmenu -config ~/hyprtk/rofi/config-icon.rasi -no-show-icons -width 30 -p "Run Script: ")
[ -n "$selected" ] && bash "$SCRIPT_DIR/$selected"