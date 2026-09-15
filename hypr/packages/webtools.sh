#!/bin/bash
# hyprtk-pkglist
# ── webtools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(chromium)
    AUR=(brave-bin github-desktop-bin)
    ;;
apt)
    # chromium resolves to the snap transitional on Ubuntu; brave-browser is
    # added from Brave's own apt repo (install_brave_apt below).
    PKGS=(chromium)
    ;;
dnf)
    PKGS=(chromium)
    ;;
zypper)
    PKGS=(chromium)
    ;;
xbps)
    PKGS=(chromium)
    ;;
apk)
    PKGS=(chromium)
    ;;
esac

# Brave ships no distro package; add its official apt repo on Debian/Ubuntu so
# brave-browser installs the same way the AUR package does on Arch.
install_brave_apt() {
    pkg_is_installed brave-browser && return 0
    command -v apt-get >/dev/null 2>&1 || return 0
    echo "  Enabling Brave's apt repository"
    local keyring=/usr/share/keyrings/brave-browser-archive-keyring.gpg
    local url=https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    hyprtk_run_root mkdir -p /usr/share/keyrings
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" | hyprtk_run_root tee "$keyring" >/dev/null || { echo "  ! could not fetch the Brave keyring"; return 0; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url" | hyprtk_run_root tee "$keyring" >/dev/null || { echo "  ! could not fetch the Brave keyring"; return 0; }
    else
        echo "  ! curl/wget missing — skipping Brave"
        return 0
    fi
    printf 'deb [signed-by=%s] https://brave-browser-apt-release.s3.brave.com/ stable main\n' "$keyring" \
        | hyprtk_run_root tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    hyprtk_run_root apt-get update
    pkg_install brave-browser
}

if [ "${1:-}" = "--list" ]; then
    printf '%s ' "${PKGS[@]}" "${AUR[@]}"
    [ "$HYPRTK_PM" = apt ] && printf 'brave-browser '
    echo; exit 0
fi

echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
[ "$HYPRTK_PM" = apt ] && install_brave_apt
echo ""
