#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "HyprViz"

echo ""
echo " Hyprland Configuration Tool "
echo ""
cd $HOME/Downloads/yay-git/src/
git clone https://aur.archlinux.org/hyprviz-bin.git
cd hyprviz-bin
makepkg -si
echo ""