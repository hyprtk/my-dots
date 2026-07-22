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

figlet -f 3d "Wallpapers"
echo ""
echo ""
echo "-> Install wallapers"
while true; do
    read -p "Do you want to clone the wallpapers? If not, the script will install 3 default wallpapers to ~/Pictures/Wallpapers/ (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ -d ~/Pictures/Wallpapers/ ]; then
                echo "Wallpaper folder already exists."
            else
                git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
                echo "Wallpapers installed."
            fi
            echo "Wallpapers installed."
        break;;
        [Nn]* )
            if [ -d ~/Pictures/Wallpapers/ ]; then
                echo "Wallpapers folder already exists."
            else
                mkdir ~/Pictures/Wallpapers
            fi
            cp ~/hyprtk/Wallpapers/* ~/Pictures/Wallpapers
            echo "Default wallpapers installed."
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done
echo ""
