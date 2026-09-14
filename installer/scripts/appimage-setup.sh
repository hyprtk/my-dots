#!/bin/bash
#
#
# AppImage support (FUSE + AppImageLauncher) and the base build tools.
# Distro-aware: FUSE/base-devel come from each repo; AppImageLauncher is AUR on
# Arch and a vendor package (PPA/repo) elsewhere, so the install is best-effort.
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

echo ""
case "$HYPRTK_PM" in
    pacman)
        pkg_install fuse2 fuse
        pkg_install base-devel git
        aur_install appimagelauncher
        ;;
    apt)
        pkg_install libfuse2
        pkg_install appimagelauncher
        ;;
    dnf)
        pkg_install fuse fuse-libs
        pkg_install appimagelauncher
        ;;
    zypper)
        pkg_install libfuse2
        ;;
    xbps)
        pkg_install fuse fuse3
        ;;
    apk)
        pkg_install fuse fuse3
        ;;
esac
hyprtk_run_root modprobe fuse 2>/dev/null || true
echo ""
