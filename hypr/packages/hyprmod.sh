#!/bin/bash
# hyprtk-pkglist
# ── hyprmod ─────────────────────────────────────────────────────────
# HyprMod is a native GTK4/libadwaita settings app for Hyprland. It is an
# AUR package, so it only exists on Arch and is installed with the AUR helper.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

AUR=()
[ "$HYPRTK_PM" = pacman ] && AUR=(hyprmod)

if [ "${1:-}" = "--list" ]; then printf '%s ' "${AUR[@]}"; echo; exit 0; fi

echo ""
echo " HyprMod — Hyprland settings app "
echo ""
if [ "$HYPRTK_PM" != pacman ]; then
    echo "  ! hyprmod is Arch/AUR only — skipping." >&2
    echo "    Upstream: https://github.com/BlueManCZ/hyprmod" >&2
    exit 0
fi
aur_install "${AUR[@]}"
echo ""
