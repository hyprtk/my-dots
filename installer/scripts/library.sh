#!/bin/bash
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# Multi-distro package helpers. The package layer now delegates to
# installer/scripts/pkgmanager.sh (pacman/apt/dnf/zypper/xbps/apk/…), while the
# historic _isInstalled* / _installPackages* names are kept so existing callers
# (1-install.sh, installupdates.sh) keep working.

# shellcheck source=installer/scripts/pkgmanager.sh
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

# ------------------------------------------------------
# Is package installed  (echoes 0 == true / 1 == false)
# ------------------------------------------------------
_isInstalledPacman() {
    if pkg_is_installed "$1"; then
        echo 0
    else
        echo 1
    fi
}

# Historical AUR check — now just "is the package installed", so it works on any
# package manager. AUR-only packages simply report not-installed off Arch.
_isInstalledYay() {
    _isInstalledPacman "$1"
}

# ------------------------------------------------------
# Install all packages that are not already present
# ------------------------------------------------------
_installPackagesPacman() {
    local toInstall=()
    local pkg
    for pkg in "$@"; do
        if pkg_is_installed "$pkg"; then
            echo "${pkg} is already installed."
            continue
        fi
        toInstall+=("$pkg")
    done

    if [ "${#toInstall[@]}" -eq 0 ]; then
        return
    fi

    printf "Packages not installed:\n%s\n" "${toInstall[*]}"
    pkg_install "${toInstall[@]}"
}

# Repository-equivalent of the old AUR helper path. Callers that need real AUR
# packages use pkgmanager's aur_install directly.
_installPackagesYay() {
    _installPackagesPacman "$@"
}

# ------------------------------------------------------
# Create symbolic links
# ------------------------------------------------------
_installSymLink() {
    name="$1"
    symlink="$2";
    linksource="$3";
    linktarget="$4";

    if [ -L "${symlink}" ]; then
        rm -f -- "${symlink}"
        ln -s "${linksource}" "${symlink}"
        echo "Symlink ${linksource} -> ${symlink} created."
    elif [ -d "${symlink}" ] && [ ! -L "${symlink}" ]; then
        # Only reachable for a real directory; never use a trailing slash on
        # rm -rf (GNU rm would follow a symlink-to-dir and delete its target).
        rm -rf -- "${symlink}"
        ln -s "${linksource}" "${symlink}"
        echo "Symlink for directory ${linksource} -> ${symlink} created."
    elif [ -f "${symlink}" ]; then
        rm -f -- "${symlink}"
        ln -s "${linksource}" "${symlink}"
        echo "Symlink to file ${linksource} -> ${symlink} created."
    else
        ln -s "${linksource}" "${symlink}"
        echo "New symlink ${linksource} -> ${symlink} created."
    fi
}
