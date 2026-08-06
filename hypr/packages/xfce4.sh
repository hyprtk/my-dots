#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "XFCE4"

echo " XFCE4 "

# Install or update pacman packages
_installOrUpdatePacman xfce4
_installOrUpdatePacman xfce4-goodies
_installOrUpdatePacman parole

# Install or update yay packages
_installOrUpdateYay tumbler-extra-thumbnailers