#!/bin/bash
# hyprtk-pkglist
# ── hyprland ─────────────────────────────────────────────────────────
# Core compositor + the Wayland/GTK plumbing the dotfiles rely on.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost
          nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl
          libadwaita gtk3 gtk-layer-shell gtk4 desktop-file-utils python python-pip
          python-virtualenv python-gobject wob hyprsunset)
    AUR=(awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs
         gvfs-smb 7zip unzip unrar)
    ;;
apt)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist x11-xserver-utils
          nwg-look curl imagemagick jq bc brightnessctl playerctl
          libadwaita-1-0 libgtk-3-0 libgtk-layer-shell0 libgtk-4-1 desktop-file-utils
          python3 python3-pip python3-venv python3-gi wob hyprsunset swaylock
          gvfs-backends 7zip unzip unrar)
    ;;
dnf)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist
          xhost nwg-look curl ImageMagick jq bc
          brightnessctl playerctl libadwaita gtk3 gtk-layer-shell gtk4
          desktop-file-utils python3 python3-pip python3-virtualenv python3-gobject
          wob hyprsunset swaylock gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs
          gvfs-smb 7zip unzip unrar)
    ;;
zypper)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xhost nwg-look
          curl ImageMagick jq bc brightnessctl playerctl libadwaita-1-0
          gtk3 libgtk-layer-shell0 gtk4 desktop-file-utils python3 python3-pip
          python3-virtualenv python3-gobject wob hyprsunset swaylock gvfs
          gvfs-backends p7zip unzip unrar)
    ;;
xbps)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xhost nwg-look
          curl ImageMagick jq bc brightnessctl playerctl libadwaita
          gtk+3 gtk-layer-shell gtk4 desktop-file-utils python3 python3-pip
          python3-virtualenv python3-gobject wob hyprsunset swaylock gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb p7zip unzip unrar)
    ;;
apk)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xhost nwg-look
          curl imagemagick jq bc brightnessctl playerctl libadwaita gtk+3.0
          gtk-layer-shell gtk4.0 desktop-file-utils python3 py3-pip py3-virtualenv
          py3-gobject3 wob swaylock gvfs 7zip unzip unrar)
    ;;
esac

# ── Hyprland >= 0.55 (Ubuntu) ──────────────────────────────────────────────
# The dotfiles' config is Lua-based, and Hyprland only reads hyprland.lua from
# 0.55 onward. Ubuntu's archive ships an older Hyprland (26.04: 0.53.3), so the
# Ubuntu path installs from the maintained community PPA; Debian (no such PPA)
# falls through to the archive package with a warning.
_hyprland_version() {
    dpkg-query -W -f '${Version}' hyprland 2>/dev/null | sed -E 's/[+~-].*$//'
}

_hyprland_ge_055() {
    local v major minor
    v="$(_hyprland_version)"
    [ -n "$v" ] || return 1
    major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
    [ "${major:-0}" -gt 0 ] 2>/dev/null && return 0
    [ "${minor:-0}" -ge 55 ] 2>/dev/null
}

_hyprtk_is_ubuntu() {
    [ -r /etc/os-release ] || return 1
    local id like
    # Strip both quote styles — os-release (e.g. Gentoo) may use single quotes.
    id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d "\"'")"
    like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d "\"'")"
    case "$id $like" in *ubuntu*) return 0 ;; *) return 1 ;; esac
}

install_hyprland_apt() {
    if _hyprland_ge_055; then
        echo "  Hyprland $(_hyprland_version) already provides the Lua config (>= 0.55)"
        return 0
    fi
    if ! _hyprtk_is_ubuntu; then
        echo "  ! Debian ships Hyprland < 0.55 (no Lua config); installing the archive package — see PORTABILITY.md"
        return 0
    fi
    echo "  Enabling the cppiber/hyprland PPA for Hyprland >= 0.55 (Lua config)"
    # Prefer adding the PPA by keyring + source: `add-apt-repository` needs
    # software-properties-common and a reachable Launchpad API, and fails on
    # minimal/containerised Ubuntu & Mint ("codename isn't currently supported").
    if ! hyprtk_apt_add_ppa cppiber/hyprland A54D23B62FF3FCC76EFF71E8FDBAAA1CF0CCF48E; then
        pkg_install software-properties-common
        hyprtk_run_root add-apt-repository -y ppa:cppiber/hyprland
        hyprtk_run_root apt-get update
    fi
    # The PPA's libhyprcursor1/libudis86.1 supersede the archive's
    # libhyprcursor0/libudis86-0 without declaring Replaces, so the file lists
    # collide; --force-overwrite lets the upgrade through.
    hyprtk_run_root apt-get -o Dpkg::Options::=--force-overwrite install -y hyprland
    hyprtk_run_root apt-get -o Dpkg::Options::=--force-overwrite -f install -y
}

# Void Linux does not package Hyprland (a packaging-philosophy conflict), so the
# xbps list has no `hyprland` to install. The documented path is the community
# binary repository; the installer does not add a third-party repo on its own, so
# print the exact steps when the compositor is still missing.
note_void_hyprland() {
    [ "$HYPRTK_PM" = xbps ] || return 0
    pkg_is_installed hyprland && return 0
    echo "  ! Void Linux does not package Hyprland. Add the community repository, then re-run:" >&2
    echo "      echo 'repository=https://github.com/void-land/hyprland-void-packages/releases/latest/download/' \\" >&2
    echo "        | sudo tee /etc/xbps.d/hyprland-packages.conf" >&2
    echo "      sudo xbps-install -S && sudo xbps-install -Sy hyprland xdg-desktop-portal-hyprland" >&2
    echo "    (or build from source: https://github.com/void-land/hyprland-void-packages)" >&2
}

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Hyprland "
[ "$HYPRTK_PM" = apt ] && install_hyprland_apt
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
note_void_hyprland
