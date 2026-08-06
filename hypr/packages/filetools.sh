#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "File Tools"

echo " File Tools"

# Install or update pacman packages
_installOrUpdatePacman thunar
_installOrUpdatePacman mousepad

echo ""

# Install or update yay packages
_installOrUpdateYay thunar-shares-plugin
echo ""