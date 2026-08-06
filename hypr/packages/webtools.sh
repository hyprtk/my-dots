#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "WebTools"

echo ""

# Install or update pacman packages
_installOrUpdatePacman chromium

echo ""

# Install or update yay packages
_installOrUpdateYay brave-bin
_installOrUpdateYay github-desktop-bin
echo ""