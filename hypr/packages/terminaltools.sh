#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "Term Tools"
echo " Terminal Tools"
_install_pacman eza micro xfce4-terminal btop alacritty kitty starship ranger nano figlet neovim
_install_aur fastfetch
echo ""
