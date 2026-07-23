#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "File Tools"
echo " File Tools"
_install_pacman thunar mousepad
echo ""
_install_aur thunar-shares-plugin
echo ""
