#!/bin/bash
# hyprtk-pkglist
# ── filetools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(thunar mousepad)
    AUR=(thunar-shares-plugin)
    ;;
apt)
    PKGS=(thunar mousepad)
    ;;
dnf)
    PKGS=(Thunar mousepad)
    ;;
zypper)
    PKGS=(thunar mousepad thunar-shares-plugin)
    ;;
xbps)
    PKGS=(Thunar mousepad)
    ;;
apk)
    PKGS=(thunar mousepad)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " File Tools"
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
