#!/bin/bash
# hyprtk-pkglist
# ── system ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts
          otf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd eza
          python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp
          pcp-gui gtk4-layer-shell hyprpicker)
    AUR=(bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek
         pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers)
    ;;
apt)
    PKGS=(sddm blueman fzf font-manager fonts-font-awesome fonts-firacode eza
          python3-pip python3-psutil python3-rich python3-click python3-venv
          xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober
          policykit-1-gnome gnome-keyring libgtk4-layer-shell0 hyprpicker)
    ;;
dnf)
    # polkit-gnome is not packaged on Fedora; mate-polkit provides the agent.
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts-all fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober mate-polkit gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
zypper)
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs           xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          libgtk4-layer-shell0 hyprpicker)
    ;;
xbps)
    PKGS=(sddm blueman fzf fontmanager font-awesome font-firacode eza python3-pip
          python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
apk)
    PKGS=(sddm blueman fzf font-manager font-awesome font-fira-code-nerd eza py3-pip
          py3-psutil py3-rich py3-click xdg-desktop-portal-gtk xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gtk4-layer-shell
          hyprpicker)
    ;;
esac

# Debian 13 dropped policykit-1-gnome; mate-polkit provides the agent there.
# (The session wrapper hypr/scripts/polkit-agent.sh finds whichever is present.)
if [ "$HYPRTK_PM" = apt ] && command -v apt-get >/dev/null 2>&1 \
    && ! apt-get install -s -y policykit-1-gnome >/dev/null 2>&1; then
    PKGS=("${PKGS[@]/policykit-1-gnome/mate-polkit}")
fi

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo ""
echo " System Packages "
echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""

# Performance Co-Pilot PMDA modules are Arch-only.
if [ "$HYPRTK_PM" = pacman ]; then
    # shellcheck disable=SC2046
    pkg_install $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null) || true
fi

# papirus-folders CLI — bundled with the dotfiles; fall back to the upstream
# installer fetched to a temp file (never a blind pipe-to-shell) off-tree.
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
