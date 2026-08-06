#!/bin/bash
cache_file="$HOME/.cache/.themestyle.sh"
variant_dir="$HOME/hyprtk/configs/rofi/variants"
symlink="$HOME/hyprtk/configs/rofi/variant.rasi"

if [ -f "$cache_file" ]; then
    content=$(cat "$cache_file")
    IFS=';' read -ra arr <<< "$content"
    if [ ${#arr[@]} -ge 1 ] && [ -n "${arr[0]}" ]; then
        theme="${arr[0]#/}"
    else
        theme="hyprtk"
    fi
else
    theme="hyprtk"
fi

if [ -f "$variant_dir/$theme.rasi" ]; then
    ln -sf "variants/$theme.rasi" "$symlink"
else
    ln -sf "variants/hyprtk.rasi" "$symlink"
fi
