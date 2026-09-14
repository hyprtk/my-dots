#!/bin/bash
# ----------------------------------------------------- 
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

selected=$(cat ~/.config/BraveSoftware/Brave-Browser/Default/Bookmarks | grep '"url":' | awk '{print $2}' | sed 's/"//g' | rofi -dmenu -p "Select a Brave Bookmark")

if [ -n "$selected" ]; then
    brave -- "$selected"
fi
