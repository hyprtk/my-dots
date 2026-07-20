#!/bin/bash
figlet -f 3d "HyprViz"
echo ""
echo " Hyprland Configuration Tool "
echo ""
tmpdir=$(mktemp -d)
cd "$tmpdir"
git clone https://aur.archlinux.org/hyprviz-bin.git
cd hyprviz-bin
makepkg -si
rm -rf "$tmpdir"
echo ""