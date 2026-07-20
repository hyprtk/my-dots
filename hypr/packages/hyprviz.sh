#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "HyprViz"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
echo ""
tmpdir=$(mktemp -d)
cd "$tmpdir"
git clone https://aur.archlinux.org/hyprviz-bin.git
cd hyprviz-bin
makepkg -si
rm -rf "$tmpdir"
echo ""