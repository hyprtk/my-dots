#!/bin/bash
# Library of helper functions for the unified installer

# Get the directory of this script (uses LIB_DIR to avoid clobbering caller's SCRIPT_DIR)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/headers.sh"
source "$LIB_DIR/distro-detection.sh"

# ------------------------------------------------------
# Function: Is package installed
# ------------------------------------------------------
_isInstalledPacman() {
    local package="$1"
    local check
    check="$(sudo pacman -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} ")"
    if [ -n "${check}" ]; then
        echo 0
        return
    fi
    echo 1
    return
}

_isInstalledYay() {
    local package="$1"
    local check
    check="$(yay -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} ")"
    if [ -n "${check}" ]; then
        echo 0
        return
    fi
    echo 1
    return
}

# ------------------------------------------------------
# Function: Install or update pacman package
# ------------------------------------------------------
_installOrUpdatePacman() {
    local package="$1"

    if [[ $(_isInstalledPacman "${package}") == 0 ]]; then
        echo "${package} is already installed. Checking for updates...";
        if pacman -Qu "${package}" > /dev/null 2>&1; then
            echo "Updating ${package}...";
            sudo pacman --noconfirm -S "${package}" || true
        else
            echo "${package} is up to date.";
        fi
        return 0
    fi

    echo "Installing ${package}...";
    sudo pacman --noconfirm -S "${package}" || true
}

# ------------------------------------------------------
# Function: Install or update yay package
# ------------------------------------------------------
_installOrUpdateYay() {
    local package="$1"

    if [[ $(_isInstalledYay "${package}") == 0 ]]; then
        echo "${package} is already installed. Checking for updates...";
        if yay -Qu "${package}" > /dev/null 2>&1; then
            echo "Updating ${package}...";
            yay --noconfirm -S "${package}" || true
        else
            echo "${package} is up to date.";
        fi
        return 0
    fi

    echo "Installing ${package}...";
    yay --noconfirm -S "${package}" || true
}

# ------------------------------------------------------
# Function: Check and install/update oh-my-zsh
# ------------------------------------------------------
_checkAndInstallOhMyZsh() {
    echo "Checking oh-my-zsh..."

    # Skip if already installed
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh is already installed. Skipping."
        return 0
    fi

    echo "Installing oh-my-zsh..."
    if command -v curl > /dev/null 2>&1; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>&1 || {
            echo "Warning: oh-my-zsh installation failed. Continuing..."
            return 0
        }
    else
        echo "Warning: curl not found. Skipping oh-my-zsh installation."
        return 0
    fi
    echo "oh-my-zsh installed successfully."
    return 0
}

# ------------------------------------------------------
# Function: Check and install zsh plugin
# ------------------------------------------------------
_installZshPlugin() {
    local plugin_name="$1"
    local plugin_url="$2"
    local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/${plugin_name}"

    echo "Checking ${plugin_name}..."

    # Skip if oh-my-zsh not installed
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "Warning: oh-my-zsh not installed. Skipping ${plugin_name}."
        return 0
    fi

    # Skip if plugin already installed
    if [ -d "$plugin_dir" ]; then
        echo "${plugin_name} is already installed. Skipping."
        return 0
    fi

    echo "Installing ${plugin_name}..."
    if command -v git > /dev/null 2>&1; then
        git clone "$plugin_url" "$plugin_dir" 2>&1 || {
            echo "Warning: Failed to install ${plugin_name}. Continuing..."
            return 0
        }
    else
        echo "Warning: git not found. Skipping ${plugin_name} installation."
        return 0
    fi
    echo "${plugin_name} installed successfully."
    return 0
}

# ------------------------------------------------------
# Create symbolic links (non-interactive)
# ------------------------------------------------------
_installSymLink() {
    local name="$1"
    local symlink="$2"
    local linksource="$3"
    local linktarget="$4"

    # Remove existing symlink, directory, or file
    if [ -L "${symlink}" ]; then
        rm -f "${symlink}" || true
    elif [ -d "${symlink}" ]; then
        rm -rf "${symlink}" || true
    elif [ -f "${symlink}" ]; then
        rm -f "${symlink}" || true
    fi

    # Create parent directory if needed
    local parent_dir
    parent_dir="$(dirname "${linktarget}")"
    mkdir -p "${parent_dir}" 2>/dev/null || true

    # Create the symlink
    if ln -s "${linksource}" "${linktarget}" 2>/dev/null; then
        if type gum_log &>/dev/null; then
            gum_log "Symlink ${name}: ${linksource} -> ${linktarget}" success
        else
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} Symlink ${COLOR_CYAN}${name}${COLOR_RESET} created."
        fi
    else
        if type gum_log &>/dev/null; then
            gum_log "Failed to create symlink ${name}" warning
        else
            echo -e "  ${COLOR_YELLOW}⚠${COLOR_RESET} Failed to create symlink ${name}"
        fi
    fi
}

# ------------------------------------------------------
# Confirmation prompt (non-interactive, always proceeds)
# ------------------------------------------------------
_confirmPrompt() {
    local message="$1"
    if type gum_log &>/dev/null; then
        gum_log "$message" info
    else
        echo -e "${COLOR_BOLD_CYAN}→${COLOR_RESET} $message"
    fi
}
