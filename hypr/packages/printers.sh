#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Printer"

echo " Printer Packages "

# Install or update yay packages
_installOrUpdateYay cups
_installOrUpdateYay cups-pdf
_installOrUpdateYay cups-filters
_installOrUpdateYay nss-mdns
_installOrUpdateYay system-config-printer
_installOrUpdateYay cups-browsed
_installOrUpdateYay libusb
_installOrUpdateYay ipp-usb
_installOrUpdateYay xdg-utils
_installOrUpdateYay colord
_installOrUpdateYay logrotate
echo ""