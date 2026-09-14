#!/bin/bash
#
# ─────────────────────────────────────────────────────────────────
#   HYPRTK · Cleanup
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────
# Clear the package cache and remove orphaned packages. Distro-aware.

_pm=""
command -v pacman       >/dev/null 2>&1 && _pm=pacman
[ -z "$_pm" ] && command -v apt-get      >/dev/null 2>&1 && _pm=apt
[ -z "$_pm" ] && command -v dnf          >/dev/null 2>&1 && _pm=dnf
[ -z "$_pm" ] && command -v zypper       >/dev/null 2>&1 && _pm=zypper
[ -z "$_pm" ] && command -v xbps-install >/dev/null 2>&1 && _pm=xbps
[ -z "$_pm" ] && command -v apk          >/dev/null 2>&1 && _pm=apk

case "$_pm" in
    pacman)
        sudo pacman -Sc --noconfirm
        sudo bash -c 'pacman -Qtdq | pacman -Rns --noconfirm -'
        ;;
    apt)
        sudo apt-get autoremove -y
        sudo apt-get autoclean -y
        ;;
    dnf)
        sudo dnf autoremove -y
        sudo dnf clean all
        ;;
    zypper)
        sudo zypper --non-interactive clean -a
        ;;
    xbps)
        sudo xbps-remove -Oo
        ;;
    apk)
        sudo apk cache clean
        ;;
    *)
        echo "Unknown package manager — nothing to clean."
        ;;
esac
