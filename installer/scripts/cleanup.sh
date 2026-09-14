#!/bin/bash
#
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# Clear the package cache and remove orphaned packages. Distro-aware: uses the
# matching cleanup commands for the detected package manager.
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

echo " WARNING!! This will clean out your package cache / unneeded installs / orphans"
case "$HYPRTK_PM" in
    pacman)
        hyprtk_run_root pacman -Sc --noconfirm 2>/dev/null
        hyprtk_run_root bash -c 'pacman -Qtdq | pacman -Rns --noconfirm -' 2>/dev/null
        ;;
    apt)
        hyprtk_run_root apt-get autoremove -y 2>/dev/null
        hyprtk_run_root apt-get autoclean -y 2>/dev/null
        ;;
    dnf)
        hyprtk_run_root dnf autoremove -y 2>/dev/null
        hyprtk_run_root dnf clean all 2>/dev/null
        ;;
    zypper)
        hyprtk_run_root zypper --non-interactive clean -a 2>/dev/null
        ;;
    xbps)
        hyprtk_run_root xbps-remove -Oo 2>/dev/null
        ;;
    apk)
        hyprtk_run_root apk cache clean 2>/dev/null
        ;;
esac

# Remove gamemode flag
if [ -f ~/.cache/gamemode ]; then
    rm ~/.cache/gamemode
    echo ":: ~/.cache/gamemode removed"
fi
