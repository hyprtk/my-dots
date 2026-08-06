#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Hyprland"

echo " Hyprland "

# Install or update pacman packages
_installOrUpdatePacman hyprland
_installOrUpdatePacman xdg-desktop-portal-wlr
_installOrUpdatePacman swayidle
_installOrUpdatePacman swappy
_installOrUpdatePacman cliphist
_installOrUpdatePacman xorg-xhost
_installOrUpdatePacman nwg-look
_installOrUpdatePacman mission-center
_installOrUpdatePacman curl
_installOrUpdatePacman imagemagick
_installOrUpdatePacman jq
_installOrUpdatePacman bc
_installOrUpdatePacman brightnessctl
_installOrUpdatePacman playerctl
_installOrUpdatePacman libadwaita
_installOrUpdatePacman gtk-layer-shell
_installOrUpdatePacman python
_installOrUpdatePacman python-pip
_installOrUpdatePacman python-virtualenv
_installOrUpdatePacman python-gobject
_installOrUpdatePacman gtk4
_installOrUpdatePacman wob

echo ""

# Install or update yay packages
_installOrUpdateYay awww
_installOrUpdateYay swaylock-effects
_installOrUpdateYay gvfs-afc
_installOrUpdateYay gvfs-goa
_installOrUpdateYay gvfs-gphoto2
_installOrUpdateYay gvfs-mtp
_installOrUpdateYay gvfs-nfs
_installOrUpdateYay gvfs-smb
_installOrUpdateYay 7zip
_installOrUpdateYay unzip
_installOrUpdateYay unrar
_installOrUpdateYay waybar-git

