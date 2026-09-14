#!/bin/bash
# hyprtk-pkglist
# ── terminaltools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

PKGS=(eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim fastfetch)
AUR=()
[ "$HYPRTK_PM" = pacman ] && AUR=(fastfetch)

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Terminal Tools"
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""
