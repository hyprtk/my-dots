#!/bin/bash
_install_pacman() {
    local missing=()
    for pkg in "$@"; do
        if pacman -Q "$pkg" &>/dev/null 2>&1; then
            echo "  $pkg already installed, skipping."
        else
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        sudo pacman -S --noconfirm "${missing[@]}"
    fi
}

_install_aur() {
    local missing=()
    for pkg in "$@"; do
        if pacman -Q "$pkg" &>/dev/null 2>&1; then
            echo "  $pkg already installed, skipping."
        else
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        yay -S --noconfirm "${missing[@]}"
    fi
}

figlet -f 3d "Sys Theming"
echo ""
echo " Configure sddm theme "
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
echo ""
sudo rm -rf /usr/share/grub/themes/*
sudo rm -rf /boot/grub/themes/*
echo ""
sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""
cp ~/hyprtk/default.png ~/.cache/current-wallpaper.png
echo ""
sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/
echo "Current wallpaper copied into sddm theme folder"
echo ""
echo ""
sudo cp ~/hyprtk/sddm/theme.conf /usr/share/sddm/themes/Sugar-Candy/
echo "File theme.conf updated in /usr/share/sddm/themes/Sugar-Candy/"
echo ""
echo ""
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
echo ""
echo " Configure grub theme "
echo ""
echo " Enable OS-Prober "
sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo ""
sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
echo ""
echo ""
echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"'| sudo tee -a /etc/default/grub
echo -e 'GRUB_COLOR_NORMAL="white/black"'| sudo tee -a /etc/default/grub
echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"'| sudo tee -a /etc/default/grub
echo ""
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo ""
echo " Disable OS-Prober "
sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo ""
echo " GRUB & SDDM Updated with current wallpaper "
