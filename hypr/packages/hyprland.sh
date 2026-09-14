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
          nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl
          libadwaita-1-0 libgtk-3-0 gtk-layer-shell libgtk-4-1 desktop-file-utils
          python3 python3-pip python3-venv python3-gi wob hyprsunset swaylock
          gvfs-backends 7zip unzip unrar)
    ;;
dnf)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist
          xorg-x11-server-utils nwg-look mission-center curl ImageMagick jq bc
          brightnessctl playerctl libadwaita gtk3 gtk-layer-shell gtk4
          desktop-file-utils python3 python3-pip python3-virtualenv python3-gobject
          wob hyprsunset swaylock gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs
          gvfs-smb p7zip unzip unrar)
    ;;
zypper)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xhost nwg-look
          mission-center curl ImageMagick jq bc brightnessctl playerctl libadwaita-1-0
          gtk3 gtk-layer-shell gtk4 desktop-file-utils python3 python3-pip
          python3-virtualenv python3-gobject wob hyprsunset swaylock gvfs
          gvfs-backends p7zip unzip unrar)
    ;;
xbps)
    PKGS=(hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xhost nwg-look
          mission-center curl ImageMagick jq bc brightnessctl playerctl libadwaita
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

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo " Hyprland "
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
