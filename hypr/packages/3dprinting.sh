#!/bin/bash
# hyprtk-pkglist
# ── 3dprinting ─────────────────────────────────────────────────────────
# Slicers are AUR/Flatpak-only; on non-Arch the install is a no-op with a hint.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

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
