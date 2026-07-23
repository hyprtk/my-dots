#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "WebTools"
echo ""
_install_pacman chromium
_install_aur brave-bin github-desktop-bin
echo ""
