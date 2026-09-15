#!/bin/bash
# hyprtk-pkglist
# ── printers ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed
          libusb ipp-usb xdg-utils colord logrotate)
    ;;
apt)
    PKGS=(cups printer-driver-cups-pdf cups-filters libnss-mdns system-config-printer libusb-1.0-0
          ipp-usb xdg-utils colord logrotate)
    ;;
dnf)
    PKGS=(cups cups-pdf cups-filters nss-mdns system-config-printer libusb1 ipp-usb
          xdg-utils colord logrotate)
    ;;
zypper)
    PKGS=(cups cups-pdf cups-filters nss-mdns system-config-printer libusb-1_0-0
          ipp-usb xdg-utils colord logrotate)
    ;;
xbps)
    PKGS=(cups cups-pdf cups-filters nss-mdns system-config-printer libusb ipp-usb
          xdg-utils colord logrotate)
    ;;
apk)
    PKGS=(cups cups-pdf cups-filters nss-mdns system-config-printer libusb ipp-usb
          xdg-utils colord logrotate)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Printer Packages "
pkg_install "${PKGS[@]}"
echo ""
