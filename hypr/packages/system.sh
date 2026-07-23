#!/bin/bash

figlet -f 3d "System"
echo ""
echo " System Packages "
echo ""
_install_pacman sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker
_install_pacman $(pacman -Ssq 'pcp-pmda-*')
_install_aur bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers
echo ""
figlet -f 3d "Papyrus Folders Install"
wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
echo ""
