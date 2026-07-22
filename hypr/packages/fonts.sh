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

figlet -f 3d "Fonts"
echo ""
echo ""
echo "-> Install fonts"
while true; do
    read -p "Do you want to clone the fonts? ~/fonts (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ -d ~/.local/share/fonts/ ]; then
                echo "fonts folder does not exist."
            else
                git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
                echo "user fonts installed."
            fi
            echo "User Fonts Installed."
        break;;
        [Nn]* )
            if [ -d ~/.local/share/fonts/ ]; then
                echo "fonts folder already exists."
            else
                mkdir ~/.local/share/fonts
            fi
            sudo cp -r ~/hyprtk/fonts/* /usr/share/fonts
            sudo cp -r ~/.local/share/fonts/* /usr/share/fonts
            echo "System Fonts Installed."
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done
