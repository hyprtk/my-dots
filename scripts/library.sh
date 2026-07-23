#!/bin/bash
#
# ██       ██ ██                                      
#░██      ░░ ░██                               ██   ██
#░██       ██░██      ██████  ██████   ██████ ░░██ ██ 
#░██      ░██░██████ ░░██░░█ ░░░░░░██ ░░██░░█  ░░███  
#░██      ░██░██░░░██ ░██ ░   ███████  ░██ ░    ░██   
#░██      ░██░██  ░██ ░██    ██░░░░██  ░██      ██    
#░████████░██░██████ ░███   ░░████████░███     ██     
#░░░░░░░░ ░░ ░░░░░   ░░░     ░░░░░░░░ ░░░     ░░    
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

# ------------------------------------------------------
# Function: Is package installed (0=true, 1=false)
# ------------------------------------------------------
_isInstalledYay() {
    if pacman -Q "$1" &>/dev/null 2>&1; then
        echo 0
        return 0
    fi
    echo 1
    return 1
}

# ------------------------------------------------------
# Create symbolic links
# ------------------------------------------------------
_installSymLink() {
    local name="$1"
    local target="$2"
    local source="$3"

    if [ -L "$target" ] || [ -f "$target" ]; then
        rm -f "$target"
    elif [ -d "$target" ]; then
        rm -rf "$target"
    fi

    ln -s "$source" "$target"
    echo "Symlink $source -> $target created."
}

# ------------------------------------------------------
# Package helper: install pacman packages if missing
# ------------------------------------------------------
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
