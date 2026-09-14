#!/bin/bash
# ── hyprviz ─────────────────────────────────────────────────────────
# hyprviz-bin is an AUR package, so it only builds on Arch.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

echo ""
echo " Hyprland Configuration Tool "
echo ""
if [ "$HYPRTK_PM" != pacman ]; then
    echo "  ! hyprviz-bin is Arch/AUR only — skipping." >&2
    echo "    Build from source: https://github.com/hyprviz/hyprviz" >&2
    exit 0
fi
build="$HOME/Downloads/hyprviz"
mkdir -p "$build"
if git clone https://aur.archlinux.org/hyprviz-bin.git "$build/hyprviz-bin" && \
   [ -d "$build/hyprviz-bin" ]; then
    ( cd "$build/hyprviz-bin" && makepkg -si --noconfirm )
fi
echo ""
