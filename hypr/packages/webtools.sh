#!/bin/bash
# hyprtk-pkglist
# ── webtools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(chromium)
    AUR=(brave-bin github-desktop-bin)
    ;;
apt)
    PKGS=(chromium)
    ;;
dnf)
    PKGS=(chromium)
    ;;
zypper)
    PKGS=(chromium)
    ;;
xbps)
    PKGS=(chromium)
    ;;
apk)
    PKGS=(chromium)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""
