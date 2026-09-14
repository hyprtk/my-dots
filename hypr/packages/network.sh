#!/bin/bash
# hyprtk-pkglist
# ── network ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc
          gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb
          gvfs-wsdd ntfs-3g samba)
    ;;
apt)
    PKGS=(network-manager network-manager-gnome git freerdp2-x11 curl gvfs
          gvfs-backends ntfs-3g samba)
    ;;
dnf)
    PKGS=(NetworkManager network-manager-applet git freerdp curl gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb ntfs-3g samba)
    ;;
zypper)
    PKGS=(NetworkManager NetworkManager-applet git freerdp curl gvfs gvfs-backends
          ntfs-3g samba)
    ;;
xbps)
    PKGS=(NetworkManager network-manager-applet git freerdp curl gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb ntfs-3g samba)
    ;;
apk)
    PKGS=(networkmanager networkmanager-wifi network-manager-applet git freerdp curl
          gvfs ntfs-3g samba)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Network Packages "
pkg_install "${PKGS[@]}"
echo ""
