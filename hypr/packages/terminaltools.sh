#!/bin/bash
# hyprtk-pkglist
# ── terminaltools ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

PKGS=(eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim fastfetch)
AUR=()
case "$HYPRTK_PM" in
    pacman) AUR=(fastfetch) ;;
    # openSUSE names the editor micro-editor; the rest of the list is shared.
    zypper) PKGS=(eza micro-editor xfce4-terminal btop alacritty kitty starship
                  ranger nano neovim fastfetch) ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

# fastfetch is not in the Ubuntu 24.04 (noble) or Debian archives; on the Ubuntu
# family add the community PPA that carries it, but only when it does not
# already resolve (so a later release that packages it is left alone).
if [ "$HYPRTK_PM" = apt ] && hyprtk_is_ubuntu_family && \
   ! apt-get install -s -y fastfetch >/dev/null 2>&1; then
    hyprtk_apt_add_ppa zhangsongcui3371/fastfetch EB65EE19D802F3EB1A13CFE47E2E5CB4D4865F21 || true
fi

echo " Terminal Tools"
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""
