#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "3D Printing"

echo ""
echo " 3D Printing "
echo ""

# Install or update yay packages
_installOrUpdateYay orca-slicer-bin
_installOrUpdateYay bambustudio-bin
echo ""