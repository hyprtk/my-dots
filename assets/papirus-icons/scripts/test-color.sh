#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# 1. Read the wallpaper path from pywal's cache
# -----------------------------------------------------------------------------
WALLPAPER=$(head -n1 ~/.cache/wal/wal)

if [ ! -f "$WALLPAPER" ]; then
    echo "ERROR: Wallpaper file not found: $WALLPAPER"
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Get the most dominant color from the wallpaper
# -----------------------------------------------------------------------------
get_dominant_color() {
    local img="$1"
    # Reduce to 16 colours and get histogram; pick the most frequent one
    local hist
    hist=$(magick "$img" -colors 16 -format "%c" histogram:info: 2>/dev/null)
    if [ -z "$hist" ]; then
        # Fallback: average colour (1x1 pixel)
        local avg
        avg=$(magick "$img" -resize 1x1! -format "%[pixel:p{0,0}]" info: 2>/dev/null)
        echo "$avg" | grep -o '#[0-9A-Fa-f]\{6\}' | head -n1
        return
    fi
    # Sort by count (first field) descending and take the top line
    local top
    top=$(echo "$hist" | sort -nr | head -n1)
    # Extract the hex code (6 characters after '#')
    local hex
    hex=$(echo "$top" | grep -o '#[0-9A-Fa-f]\{6\}' | head -n1)
    if [ -z "$hex" ]; then
        # Fallback: average colour
        local avg
        avg=$(magick "$img" -resize 1x1! -format "%[pixel:p{0,0}]" info: 2>/dev/null)
        hex=$(echo "$avg" | grep -o '#[0-9A-Fa-f]\{6\}' | head -n1)
    fi
    echo "$hex"
}

DOMINANT_HEX=$(get_dominant_color "$WALLPAPER")
if [ -z "$DOMINANT_HEX" ]; then
    echo "ERROR: Could not extract a dominant colour from the wallpaper."
    exit 1
fi
echo "Dominant colour: $DOMINANT_HEX"

# -----------------------------------------------------------------------------
# 3. Predefined colour palette (colour name → hex)
# -----------------------------------------------------------------------------
declare -A colors=(
    [frappe-blue]="#8caaee"
    [frappe-flamingo]="#eebebe"
    [frappe-green]="#a6d189"
    [frappe-lavender]="#babbf1"
    [frappe-maroon]="#ea999c"
    [frappe-mauve]="#ca9ee6"
    [frappe-peach]="#ef9f76"
    [frappe-pink]="#f4b8e4"
    [frappe-red]="#e78284"
    [frappe-rosewater]="#f2d5cf"
    [frappe-sapphire]="#85c1dc"
    [frappe-sky]="#99d1db"
    [frappe-teal]="#81c8be"
    [frappe-yellow]="#e5c890"
    [latte-blue]="#1e66f5"
    [latte-flamingo]="#dd7878"
    [latte-green]="#40a02b"
    [latte-lavender]="#7287fd"
    [latte-maroon]="#e64553"
    [latte-mauve]="#8839ef"
    [latte-peach]="#fe640b"
    [latte-pink]="#ea76cb"
    [latte-red]="#d20f39"
    [latte-rosewater]="#dc8a78"
    [latte-sapphire]="#209fb5"
    [latte-sky]="#04a5e5"
    [latte-teal]="#179299"
    [latte-yellow]="#df8e1d"
    [macchiato-blue]="#8aadf4"
    [macchiato-flamingo]="#f0c6c6"
    [macchiato-green]="#a6da95"
    [macchiato-lavender]="#b7bdf8"
    [macchiato-maroon]="#ee99a0"
    [macchiato-mauve]="#c6a0f6"
    [macchiato-peach]="#f5a97f"
    [macchiato-pink]="#f5bde6"
    [macchiato-red]="#ed8796"
    [macchiato-rosewater]="#f4dbd6"
    [macchiato-sapphire]="#7dc4e4"
    [macchiato-sky]="#91d7e3"
    [macchiato-teal]="#8bd5ca"
    [macchiato-yellow]="#eed49f"
    [mocha-blue]="#89b4fa"
    [mocha-flamingo]="#f2cdcd"
    [mocha-green]="#a6e3a1"
    [mocha-lavender]="#b4befe"
    [mocha-maroon]="#eba0ac"
    [mocha-mauve]="#cba6f7"
    [mocha-peach]="#fab387"
    [mocha-pink]="#f5c2e7"
    [mocha-red]="#f38ba8"
    [mocha-rosewater]="#f5e0dc"
    [mocha-sapphire]="#74c7ec"
    [mocha-sky]="#89dceb"
    [mocha-teal]="#94e2d5"
    [mocha-yellow]="#f9e2af"
)

# -----------------------------------------------------------------------------
# 4. Find the closest palette colour using CIE L*a*b* Euclidean distance
# -----------------------------------------------------------------------------
compute_lab_distance() {
    local hex1="$1"
    local hex2="$2"
    # Use ImageMagick to convert both colours to Lab and compute Euclidean distance
    magick xc:"$hex1" xc:"$hex2" -colorspace Lab \
        -format "%[fx:sqrt((u.r-v.r)^2 + (u.g-v.g)^2 + (u.b-v.b)^2)]" info: 2>/dev/null
}

min_dist=9999999
closest_color=""
for name in "${!colors[@]}"; do
    hex2="${colors[$name]}"
    dist=$(compute_lab_distance "$DOMINANT_HEX" "$hex2")
    # Ensure dist is a non‑empty numeric value (float or integer)
    if [[ -z "$dist" || ! "$dist" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        continue
    fi
    # Compare using bc (outputs 1 if true, 0 otherwise) and test against "1"
    if [ "$(echo "$dist < $min_dist" | bc -l)" = "1" ]; then
        min_dist="$dist"
        closest_color="$name"
    fi
done

# Fallback if no match was found
if [ -z "$closest_color" ]; then
    closest_color="mocha-blue"
    echo "No close match found, using fallback: $closest_color"
else
    echo "Closest colour to $DOMINANT_HEX is: $closest_color (distance $min_dist)"
fi

# -----------------------------------------------------------------------------
# 5. Apply the chosen colour to Papirus folders
# -----------------------------------------------------------------------------
~/.local/share/icons/papirus-folders.sh -C "$closest_color" -t ~/.local/share/icons/Papirus-Dark

notify-send "Icon Colors updated" "with $closest_color"