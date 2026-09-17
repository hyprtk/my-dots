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
    _apt update
    pkg_install brave-browser
}

# Fedora/RHEL and openSUSE get Brave from its official RPM repo (same source of
# truth as the apt repo above and the AUR package on Arch).
install_brave_rpm() {
    case "$HYPRTK_PM" in dnf|zypper) ;; *) return 0 ;; esac
    pkg_is_installed brave-browser && return 0
    local base=https://brave-browser-rpm-release.s3.brave.com
    echo "  Enabling Brave's RPM repository"
    hyprtk_run_root rpm --import "$base/brave-core.asc" 2>/dev/null || true
    if [ "$HYPRTK_PM" = dnf ]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$base/brave-browser.repo" \
                | hyprtk_run_root tee /etc/yum.repos.d/brave-browser.repo >/dev/null \
                || { echo "  ! could not add the Brave repo"; return 0; }
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- "$base/brave-browser.repo" \
                | hyprtk_run_root tee /etc/yum.repos.d/brave-browser.repo >/dev/null \
                || { echo "  ! could not add the Brave repo"; return 0; }
        else
            echo "  ! curl/wget missing — skipping Brave"; return 0
        fi
        hyprtk_run_root dnf install -y brave-browser || echo "  ! brave-browser install failed"
    else
        hyprtk_run_root zypper --non-interactive addrepo --refresh "$base/x86_64/" brave-browser 2>/dev/null || true
        hyprtk_run_root zypper --non-interactive --gpg-auto-import-keys install brave-browser \
            || echo "  ! brave-browser install failed"
    fi
}

if [ "${1:-}" = "--list" ]; then
    printf '%s ' "${PKGS[@]}" "${AUR[@]}"
    case "$HYPRTK_PM" in apt|dnf|zypper) printf 'brave-browser ' ;; esac
    echo; exit 0
fi

echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
[ "$HYPRTK_PM" = apt ] && install_brave_apt
case "$HYPRTK_PM" in dnf|zypper) install_brave_rpm ;; esac
echo ""
