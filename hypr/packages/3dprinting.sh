#!/bin/bash
# hyprtk-pkglist
# ── 3dprinting ─────────────────────────────────────────────────────────
# Slicers are AUR/Flatpak-only; on non-Arch the install is a no-op with a hint.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

if [ "${1:-}" = "--list" ]; then
    # AUR-only, so only Arch has resolvable names; elsewhere the install is a
    # Flatpak hint (see below) and there is nothing to list.
    [ "$HYPRTK_PM" = pacman ] && printf 'orca-slicer-bin bambustudio-bin\n'
    exit 0
fi

echo ""
echo " 3D Printing "
echo ""
case "$HYPRTK_PM" in
pacman)
    aur_install orca-slicer-bin bambustudio-bin
    ;;
*)
    echo "  ! OrcaSlicer / Bambu Studio ship as Flatpaks off Arch." >&2
    echo "    flatpak install flathub io.github.softfever.OrcaSlicer" >&2
    echo "    flatpak install flathub com.bambulab.BambuStudio" >&2
    ;;
esac
echo ""
