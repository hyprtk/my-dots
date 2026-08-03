#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Sys Tools"

echo " System Tools "

# Install or update pacman packages
_installOrUpdatePacman timeshift
_installOrUpdatePacman file-roller
_installOrUpdatePacman gparted
_installOrUpdatePacman xfce4-power-manager
_installOrUpdatePacman rofi
_installOrUpdatePacman dunst
_installOrUpdatePacman cockpit

echo ""

# Install or update yay packages
_installOrUpdateYay gnome-disk-utility
echo ""