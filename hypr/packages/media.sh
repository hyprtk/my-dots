#!/bin/bash
# hyprtk-pkglist
# ── media ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg)
    AUR=(hyprquickframe-git)
    ;;
apt)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg)
    ;;
dnf)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg-free)
    ;;
zypper)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg)
    ;;
xbps)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg)
    ;;
apk)
    PKGS=(xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Media Packages "
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""
