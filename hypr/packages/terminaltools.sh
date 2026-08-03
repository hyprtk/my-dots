#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Term Tools"

echo " Terminal Tools"

# Install or update pacman packages
_installOrUpdatePacman eza
_installOrUpdatePacman micro
_installOrUpdatePacman xfce4-terminal
_installOrUpdatePacman btop
_installOrUpdatePacman alacritty
_installOrUpdatePacman kitty
_installOrUpdatePacman starship
_installOrUpdatePacman ranger
_installOrUpdatePacman nano
_installOrUpdatePacman figlet
_installOrUpdatePacman neovim

echo ""

# Install or update yay packages
_installOrUpdateYay fastfetch
echo ""
