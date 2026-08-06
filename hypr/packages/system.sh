#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "System"

echo ""
echo " System Packages "
echo ""

# Install or update pacman packages
_installOrUpdatePacman sddm
_installOrUpdatePacman blueman
_installOrUpdatePacman pacman-contrib
_installOrUpdatePacman fzf
_installOrUpdatePacman font-manager
_installOrUpdatePacman awesome-terminal-fonts
_installOrUpdatePacman ttf-font-awesome
_installOrUpdatePacman ttf-fira-sans
_installOrUpdatePacman ttf-fira-code
_installOrUpdatePacman ttf-firacode-nerd
_installOrUpdatePacman exa
_installOrUpdatePacman python-pip
_installOrUpdatePacman python-psutil
_installOrUpdatePacman python-rich
_installOrUpdatePacman python-click
_installOrUpdatePacman xdg-desktop-portal-gtk
_installOrUpdatePacman xdg-user-dirs
_installOrUpdatePacman xdg-user-dirs-gtk
_installOrUpdatePacman os-prober
_installOrUpdatePacman polkit-gnome
_installOrUpdatePacman gnome-keyring
_installOrUpdatePacman pcp
_installOrUpdatePacman pcp-gui
_installOrUpdatePacman gtk4-layer-shell
_installOrUpdatePacman hyprpicker

# Install pcp-pmda packages
sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm

echo ""

# Install or update yay packages
_installOrUpdateYay bibata-cursor-theme
_installOrUpdateYay trizen
_installOrUpdateYay sublime-text-4
_installOrUpdateYay sddm-theme-sugar-candy-git
_installOrUpdateYay pacseek
_installOrUpdateYay tumbler-extra-thumbnailers

echo ""
print_subsection_header "Papyrus Folders Install"
wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
echo ""