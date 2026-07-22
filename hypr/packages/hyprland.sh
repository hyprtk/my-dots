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

figlet -f 3d "Hyprland"
echo " Hyprland "
_install_pacman hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl libadwaita gtk-layer-shell python python-pip python-virtualenv python-gobject gtk4 wob
_install_aur awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb 7zip unzip unrar waybar-git
