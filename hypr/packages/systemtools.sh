#!/bin/bash
# hyprtk-pkglist
# ── systemtools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(timeshift file-roller gparted xfce4-power-manager rofi cockpit)
    AUR=(gnome-disk-utility)
    ;;
apt)
    PKGS=(timeshift file-roller gparted xfce4-power-manager rofi cockpit gnome-disk-utility)
    ;;
dnf)
    PKGS=(timeshift file-roller gparted xfce4-power-manager rofi cockpit gnome-disk-utility)
    ;;
zypper)
    PKGS=(timeshift file-roller gparted xfce4-power-manager rofi cockpit gnome-disk-utility)
    ;;
xbps)
    PKGS=(timeshift file-roller gparted xfce4-power-manager rofi cockpit gnome-disk-utility)
    ;;
apk)
    PKGS=(file-roller gparted xfce4-power-manager rofi cockpit gnome-disk-utility)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " System Tools "
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""
