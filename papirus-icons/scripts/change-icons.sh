#!/usr/bin/env bash

INPUT_FILE="$HOME/.cache/wal/colors"
OUTPUT_FILE="$HOME/hyprtk/papirus-icons/scripts/folder-color.txt"
LINE_NUMBER=5 # wal colors start with a color of zero, so if i want to use color11 i must enter the value of 12 because of the row zero

# Example

#    /* Colors */         /* Row Count */
#    --color0: #242838;    1
#    --color1: #A59AAB;    2
#    --color2: #CCA0B3;    3
#    --color3: #AAC6B9;    4
#    --color4: #9CB4C7;    5
#    --color5: #D0B4C7;    6
#    --color6: #ACCFD6;    7
#    --color7: #c8c9cd;    8
#    --color8: #6a7082;    9
#    --color9: #A59AAB;    10
#    --color10: #CCA0B3;   11
#    --color11: #AAC6B9;   12
#    --color12: #9CB4C7;   13
#    --color13: #D0B4C7;   14
#    --color14: #ACCFD6;   15
#    --color15: #c8c9cd;   16

# Extract the specific line and write to output file

# Old Icon theme colors
#  [hyprtk-adwaita]="#93c0ea #3a87e5 #3a87e5 #e4e4e4"
#  [hyprtk-blue]="#5294e2 #4877b1 #1d344f #e4e4e4"
#  [hyprtk-black]="#4f4f4f #3f3f3f #c2c2c2 #dcdcdc"
#  [hyprtk-bluegrey]="#607d8b #4d646f #222c31 #e4e4e4"
#  [hyprtk-breeze]="#57b8ec #147eb8 #106796 #e4e4e4"
#  [hyprtk-brown]="#ae8e6c #957552 #3d3226 #e4e4e4"
#  [hyprtk-carmine]="#a30002 #7a0002 #390001 #e4e4e4"
#  [hyprtk-cyan]="#00bcd4 #0096aa #00424a #e4e4e4"
#  [hyprtk-darkcyan]="#45abb7 #35818a #eaeaea #e4e4e4"
#  [hyprtk-deeporange]="#eb6637 #e95420 #522413 #e4e4e4"
#  [hyprtk-green]="#87b158 #60924b #2f3e1f #e4e4e4"
#  [hyprtk-grey]="#8e8e8e #727272 #323232 #e4e4e4"
#  [hyprtk-indigo]="#5c6bc0 #3f51b5 #202543 #e4e4e4"
#  [hyprtk-magenta]="#ca71df #b259b8 #47274e #e4e4e4"
#  [hyprtk-orange]="#ee923a #dd772f #533314 #e4e4e4"
#  [hyprtk-palebrown]="#d1bfae #bea389 #a38d7b #e4e4e4"
#  [hyprtk-paleorange]="#eeca8f #c89e6b #917359 #e4e4e4"
#  [hyprtk-pink]="#f06292 #ec407a #542233 #e4e4e4"
#  [hyprtk-red]="#e25252 #bf4b4b #4f1d1d #e4e4e4"
#  [hyprtk-teal]="#16a085 #12806a #08382e #e4e4e4"
#  [hyprtk-violet]="#7e57c2 #5d399b #2c1e44 #e4e4e4"
#  [hyprtk-white]="#e4e4e4 #cccccc #4f4f4f #ffffff"
#  [hyprtk-yaru]="#676767 #973552 #e4e4e4 #ff7446"
#  [hyprtk-yellow]="#f9bd30 #e19d00 #594411 #e4e4e4"
#  [hyprtk-nordic]="#81a1c1 #5e81ac #3b4253 #eceff4"
  
sed -n "${LINE_NUMBER}p" "$INPUT_FILE" > "$OUTPUT_FILE"

# color palette (color name → hex code)
declare -A colors=(
  [frappe-blue]="#8caaee #7b89ba #313c53 #e4e4e4"
  [frappe-flamingo]="#eebebe #ea7c9e #534343 #e4e4e4"
  [frappe-green]="#a6d189 #76ac74 #3a4930 #e4e4e4"
  [frappe-lavender]="#babbf1 #7f8de3 #414154 #e4e4e4"
  [frappe-maroon]="#ea999c #c58b8e #523637 #e4e4e4"
  [frappe-mauve]="#ca9ee6 #b27cbd #473751 #e4e4e4"
  [frappe-peach]="#ef9f76 #dd815f #543829 #e4e4e4"
  [frappe-pink]="#f4b8e4 #ef78be #554050 #e4e4e4"
  [frappe-red]="#e78284 #c37678 #512e2e #e4e4e4"
  [frappe-rosewater]="#f2d5cf #cba69a #554b48 #e4e4e4"
  [frappe-sapphire]="#85c1dc #749bac #2f444d #e4e4e4"
  [frappe-sky]="#99d1db #7aa7ae #36494d #e4e4e4"
  [frappe-teal]="#81c8be #69a097 #2d4643 #e4e4e4"
  [frappe-yellow]="#e5c890 #cea600 #504632 #e4e4e4"
  [latte-blue]="#1e66f5 #1a52bf #0b2456 #e4e4e4"
  [latte-flamingo]="#dd7878 #d94e64 #4d2a2a #e4e4e4"
  [latte-green]="#40a02b #2d8324 #16380f #e4e4e4"
  [latte-lavender]="#7287fd #4e66ee #282f59 #e4e4e4"
  [latte-maroon]="#e64553 #c23f4b #51181d #e4e4e4"
  [latte-mauve]="#8839ef #772cc5 #301454 #e4e4e4"
  [latte-peach]="#fe640b #eb5108 #592304 #e4e4e4"
  [latte-pink]="#ea76cb #e64da9 #522947 #e4e4e4"
  [latte-red]="#d20f39 #b10d34 #4a0514 #e4e4e4"
  [latte-rosewater]="#dc8a78 #b86b59 #4d302a #e4e4e4"
  [latte-sapphire]="#209fb5 #1c7f8d #0b383f #e4e4e4"
  [latte-sky]="#04a5e5 #0384b6 #013a50 #e4e4e4"
  [latte-teal]="#179299 #127479 #083336 #e4e4e4"
  [latte-yellow]="#df8e1d #c97500 #4e320a #e4e4e4"
  [macchiato-blue]="#8aadf4 #798bbf #303d55 #e4e4e4"
  [macchiato-flamingo]="#f0c6c6 #eb81a5 #544545 #e4e4e4"
  [macchiato-green]="#a6da95 #76b37f #3a4c34 #e4e4e4"
  [macchiato-lavender]="#b7bdf8 #7d8fe9 #404257 #e4e4e4"
  [macchiato-maroon]="#ee99a0 #c98b92 #533638 #e4e4e4"
  [macchiato-mauve]="#c6a0f6 #ae7dcb #453856 #e4e4e4"
  [macchiato-peach]="#f5a97f #e38966 #563b2c #e4e4e4"
  [macchiato-pink]="#f5bde6 #f07bc0 #564251 #e4e4e4"
  [macchiato-red]="#ed8796 #c87b89 #532f35 #e4e4e4"
  [macchiato-rosewater]="#f4dbd6 #ccaba0 #554d4b #e4e4e4"
  [macchiato-sapphire]="#7dc4e4 #6d9db2 #2c4550 #e4e4e4"
  [macchiato-sky]="#91d7e3 #74acb5 #334b4f #e4e4e4"
  [macchiato-teal]="#8bd5ca #71aaa0 #314b47 #e4e4e4"
  [macchiato-yellow]="#eed49f #d6af00 #534a38 #e4e4e4"
  [mocha-blue]="#89b4fa #7890c3 #303f58 #e4e4e4"
  [mocha-flamingo]="#f2cdcd #ed85ab #554848 #e4e4e4"
  [mocha-green]="#a6e3a1 #76bb89 #3a4f38 #e4e4e4"
  [mocha-lavender]="#b4befe #7b8fef #3f4359 #e4e4e4"
  [mocha-maroon]="#eba0ac #c6929d #52383c #e4e4e4"
  [mocha-mauve]="#cba6f7 #b282cb #473a56 #e4e4e4"
  [mocha-peach]="#fab387 #e8916d #583f2f #e4e4e4"
  [mocha-pink]="#f5c2e7 #f07ec0 #564451 #e4e4e4"
  [mocha-red]="#f38ba8 #cd7f99 #55313b #e4e4e4"
  [mocha-rosewater]="#f5e0dc #cdafa4 #564e4d #e4e4e4"
  [mocha-sapphire]="#74c7ec #65a0b8 #294653 #e4e4e4"
  [mocha-sky]="#89dceb #6db0bb #304d52 #e4e4e4"
  [mocha-teal]="#94e2d5 #79b4a9 #344f4b #e4e4e4"
  [mocha-yellow]="#f9e2af #e0bb00 #574f3d #e4e4e4"
)

# Read hex code from plaintext file
hex=$(<~/hyprtk/papirus-icons/scripts/folder-color.txt)

# Function to convert HEX to RGB
hex_to_rgb() {
  local hex=$1
  local r=$((16#${hex:1:2}))
  local g=$((16#${hex:3:2}))
  local b=$((16#${hex:5:2}))
  echo "$r $g $b"
}

read r1 g1 b1 <<< "$(hex_to_rgb "$hex")"

# Find the closest color
min_distance=1000000
closest_color=""

for name in "${!colors[@]}"; do
  read r2 g2 b2 <<< "$(hex_to_rgb "${colors[$name]}")"
  distance=$(( (r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2) ))
  if (( distance < min_distance )); then
    min_distance=$distance
    closest_color=$name
  fi
done

echo "Closest color to $hex is: $closest_color"
~/.local/share/icons/papirus-folders.sh -C $closest_color -t ~/.local/share/icons/Papirus-Dark

notify-send "Icon Colors updated" "with $closest_color"