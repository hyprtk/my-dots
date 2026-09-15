#!/bin/bash
# hyprtk-pkglist
# ── xfce4 ─────────────────────────────────────────────────────────
# Xorg fallback desktop, kept as a safety net.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(xfce4 xfce4-goodies parole tumbler)
    AUR=(tumbler-extra-thumbnailers)
    ;;
apt)
    PKGS=(xfce4 xfce4-goodies parole tumbler)
    ;;
dnf)
    PKGS=(xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-settings
          xfce4-terminal Thunar xfce4-power-manager parole tumbler)
    ;;
zypper)
    PKGS=(patterns-xfce-xfce parole tumbler)
    ;;
xbps)
    PKGS=(xfce4 xfce4-plugins parole tumbler)
    ;;
apk)
    PKGS=(xfce4 xfce4-panel parole tumbler)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " XFCE4 "
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
