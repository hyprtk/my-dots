#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "System"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
echo ""
sudo pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker --noconfirm
sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm
echo ""
yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers --noconfirm
echo ""
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Papyrus Folders Install"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
echo ""