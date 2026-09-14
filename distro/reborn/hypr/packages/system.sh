#!/bin/bash
# hyprtk-pkglist
# ── system (RebornOS overlay) ─────────────────────────────────────────
# Same as the canonical system.sh minus the pamac/pamac-all AUR packages
# (RebornOS ships its own package manager front-ends).
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts
          ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa
          python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp
          pcp-gui gtk4-layer-shell hyprpicker)
    AUR=(bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek
         tumbler-extra-thumbnailers)
    ;;
apt)
    PKGS=(sddm blueman fzf font-manager fonts-font-awesome fonts-fira-code eza
          python3-pip python3-psutil python3-rich python3-click python3-venv
          xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober
          policykit-1-gnome gnome-keyring gtk4-layer-shell hyprpicker)
    ;;
dnf)
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
zypper)
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
xbps)
    PKGS=(sddm blueman fzf font-manager font-awesome fira-code eza python3-pip
          python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
apk)
    PKGS=(sddm blueman fzf font-manager font-awesome fira-code eza py3-pip
          py3-psutil py3-rich py3-click xdg-desktop-portal-gtk xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gtk4-layer-shell
          hyprpicker)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo ""
echo " System Packages "
echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""

if [ "$HYPRTK_PM" = pacman ]; then
    # shellcheck disable=SC2046
    pkg_install $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null) || true
fi

if [ ! -x "$_PKGDIR/../../installer/standalone/papirus-folders" ]; then
    tmp="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 https://git.io/papirus-folders-install -o "$tmp" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" --timeout=60 https://git.io/papirus-folders-install 2>/dev/null || true
    fi
    [ -s "$tmp" ] && env PREFIX="$HOME/.local" bash "$tmp" || \
        echo "  ! papirus-folders install skipped (no network / fetch failed)" >&2
    rm -f -- "$tmp"
fi
echo ""
