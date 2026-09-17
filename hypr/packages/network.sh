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
    PKGS=(network-manager network-manager-gnome git freerdp3-x11 curl gvfs
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
    # Void's gvfs is monolithic — the nfs backend ships in `gvfs` itself, so
    # there is no separate gvfs-nfs to request.
    PKGS=(NetworkManager network-manager-applet git freerdp curl gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-smb ntfs-3g samba)
    ;;
apk)
    PKGS=(networkmanager networkmanager-wifi network-manager-applet git freerdp curl
          gvfs ntfs-3g samba)
    ;;
esac

# Debian 12 ships freerdp2-x11; freerdp3-x11 is Ubuntu/newer only. Swap the
# name when the newer one is not installable (the client binary is the same).
if [ "$HYPRTK_PM" = apt ] && command -v apt-get >/dev/null 2>&1 \
    && ! apt-get install -s -y freerdp3-x11 >/dev/null 2>&1; then
    PKGS=("${PKGS[@]/freerdp3-x11/freerdp2-x11}")
fi

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Network Packages "
pkg_install "${PKGS[@]}"
echo ""
