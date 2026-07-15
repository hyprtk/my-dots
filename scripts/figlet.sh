#!/bin/bash
#
# Hyprtk-On-Arch - Generate ASCII Header
# by hyprtk (Kori Tk) (2026)
# -------------------------------------------------------------------
# Generates a professional ASCII header and copies it to clipboard.
# -------------------------------------------------------------------

read -p "Enter the header text: " mytext

cat > ~/header.txt << HEADEREOF
#########################################################
#                                                       #
#                 ${mytext}                               #
#                                                       #
#########################################################
HEADEREOF

sed -i 's/^/# /' ~/header.txt
lines=$(cat ~/header.txt)
wl-copy "$lines" 2>/dev/null
xclip -sel clip ~/header.txt 2>/dev/null

echo "Professional header copied to clipboard!"
