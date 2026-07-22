#!/bin/bash
figlet -f 3d "System"
echo ""
echo " System Packages "
echo ""
sudo pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker --noconfirm
sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm 2>/dev/null || true
echo ""
# Detect distro for AUR package selection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        manjaro)
            yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers --noconfirm
            ;;
        *)
            yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek tumbler-extra-thumbnailers --noconfirm
            ;;
    esac
else
    yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek tumbler-extra-thumbnailers --noconfirm
fi
echo ""
figlet -f 3d "Papyrus Folders Install"
wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
echo ""
