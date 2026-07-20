#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Printer"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
 sudo pacman -S cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate --noconfirm
echo ""