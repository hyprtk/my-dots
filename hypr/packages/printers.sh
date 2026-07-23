#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "Printer"
echo " Printer Packages "
_install_aur cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate
echo ""
