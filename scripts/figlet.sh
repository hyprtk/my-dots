#!/bin/bash
# -------------------------------------------------------------------
# Header Generator — Creates a styled text box and copies it
# -------------------------------------------------------------------

read -p "Enter the text for ascii encoding: " mytext
output=$(gum style --border double --border-foreground 212 --foreground 212 --padding "1 4" "$mytext")
echo "$output"
echo "$output" | wl-copy
echo "Text copied to clipboard!"
