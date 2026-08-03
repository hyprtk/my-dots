#!/bin/bash
# Library of helper functions for the unified installer

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/headers.sh"
source "$SCRIPT_DIR/distro-detection.sh"

# ------------------------------------------------------
# Function: Is package installed
# ------------------------------------------------------
_isInstalledPacman() {
    package="$1";
    check="$(sudo pacman -Qs --color always "${package}" | grep "local" | grep "${package} ")";
    if [ -n "${check}" ] ; then
        echo 0; #'0' means 'true' in Bash
        return; #true
    fi;
    echo 1; #'1' means 'false' in Bash
    return; #false
}

_isInstalledYay() {
    package="$1";
    check="$(yay -Qs --color always "${package}" | grep "local" | grep "${package} ")";
    if [ -n "${check}" ] ; then
        echo 0; #'0' means 'true' in Bash
        return; #true
    fi;
    echo 1; #'1' means 'false' in Bash
    return; #false
}

# ------------------------------------------------------
# Function Install all package if not installed
# ------------------------------------------------------
_installPackagesPacman() {
    toInstall=();
    toUpdate=();

    for pkg; do
        if [[ $(_isInstalledPacman "${pkg}") == 0 ]]; then
            echo "${pkg} is already installed. Checking for updates...";
            # Check if update is available
            if pacman -Qu "${pkg}" > /dev/null 2>&1; then
                toUpdate+=("${pkg}");
            fi
            continue;
        fi;

        toInstall+=("${pkg}");
    done;

    if [[ "${toInstall[@]}" == "" ]] && [[ "${toUpdate[@]}" == "" ]] ; then
        echo "All pacman packages are already installed and up to date.";
        return;
    fi;

    if [[ "${toInstall[@]}" != "" ]]; then
        printf "Packages to install:\n%s\n" "${toInstall[@]}";
        sudo pacman --noconfirm -S "${toInstall[@]}";
    fi
    
    if [[ "${toUpdate[@]}" != "" ]]; then
        printf "Packages to update:\n%s\n" "${toUpdate[@]}";
        sudo pacman --noconfirm -S "${toUpdate[@]}";
    fi
}

_installPackagesYay() {
    toInstall=();
    toUpdate=();

    for pkg; do
        if [[ $(_isInstalledYay "${pkg}") == 0 ]]; then
            echo "${pkg} is already installed. Checking for updates...";
            # Check if update is available
            if yay -Qu "${pkg}" > /dev/null 2>&1; then
                toUpdate+=("${pkg}");
            fi
            continue;
        fi;

        toInstall+=("${pkg}");
    done;

    if [[ "${toInstall[@]}" == "" ]] && [[ "${toUpdate[@]}" == "" ]] ; then
        echo "All AUR packages are already installed and up to date.";
        return;
    fi;

    if [[ "${toInstall[@]}" != "" ]]; then
        printf "AUR packages to install:\n%s\n" "${toInstall[@]}";
        yay --noconfirm -S "${toInstall[@]}";
    fi
    
    if [[ "${toUpdate[@]}" != "" ]]; then
        printf "AUR packages to update:\n%s\n" "${toUpdate[@]}";
        yay --noconfirm -S "${toUpdate[@]}";
    fi
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
# Function: Check if AUR package is installed
# ------------------------------------------------------
_isInstalledAur() {
    local package="$1"
    if yay -Qs "^${package}$" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------
# Function: Install AUR package if not installed
# ------------------------------------------------------
_installAurPackage() {
    local package="$1"
    local display_name="${2:-$package}"
    
    if _isInstalledAur "$package"; then
        echo "${display_name} is already installed."
        return 0
    fi
    
    echo "Installing ${display_name}..."
    yay --noconfirm -S "$package"
}

# ------------------------------------------------------
# Function: Check if directory exists
# ------------------------------------------------------
_isDirectoryExists() {
    local dir="$1"
    if [ -d "$dir" ]; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------
# Function: Check if command exists
# ------------------------------------------------------
_isCommandExists() {
    local cmd="$1"
    if command -v "$cmd" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------
# Function: Check and install/update hyprviz
# ------------------------------------------------------
_checkAndInstallHyprviz() {
    echo "Checking hyprviz..."
    
    # Skip if already installed
    if command -v hyprviz > /dev/null 2>&1 || [ -f "/usr/bin/hyprviz" ]; then
        echo "hyprviz-bin is already installed. Skipping."
        return 0
    fi
    
    # Skip if yay not available
    if ! command -v yay > /dev/null 2>&1; then
        echo "Warning: yay not found. Skipping hyprviz installation."
        return 0
    fi
    
    echo "Installing hyprviz-bin..."
    yay -S hyprviz-bin --noconfirm 2>&1 || {
        echo "Warning: Failed to install hyprviz-bin. Continuing..."
        return 0
    }
    echo "hyprviz-bin installed successfully."
    return 0
}

# ------------------------------------------------------
# Function: Check and install/update matuwall
# ------------------------------------------------------
_checkAndInstallMatuwall() {
    echo "Checking matuwall..."
    
    # Skip if already installed
    if [ -d "$HOME/.local/share/Matuwall" ]; then
        echo "Matuwall is already installed. Skipping."
        return 0
    fi
    
    # Skip if script doesn't exist
    if [ ! -f ~/hyprtk/hypr/packages/matuwall.sh ]; then
        echo "Warning: matuwall.sh not found. Skipping matuwall installation."
        return 0
    fi
    
    echo "Installing Matuwall..."
    bash ~/hyprtk/hypr/packages/matuwall.sh 2>&1 || {
        echo "Warning: Failed to install Matuwall. Continuing..."
        return 0
    }
    echo "Matuwall installed successfully."
    return 0
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
# Create symbolic links
# ------------------------------------------------------
_installSymLink() {
    name="$1"
    symlink="$2";
    linksource="$3";
    linktarget="$4";
    
    while true; do
        read -p "DO YOU WANT TO INSTALL ${name}? (Existing hyprtk will be removed!) (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                if [ -L "${symlink}" ]; then
                    rm "${symlink}" || true
                    ln -s "${linksource}" "${linktarget}" || true
                    echo -e "${COLOR_GREEN}✓${COLOR_RESET} Symlink ${COLOR_CYAN}${linksource}${COLOR_RESET} -> ${COLOR_CYAN}${linktarget}${COLOR_RESET} created."
                    echo ""
                else
                    if [ -d "${symlink}" ]; then
                        rm -rf "${symlink}/" || true
                        ln -s "${linksource}" "${linktarget}" || true
                        echo -e "${COLOR_GREEN}✓${COLOR_RESET} Symlink for directory ${COLOR_CYAN}${linksource}${COLOR_RESET} -> ${COLOR_CYAN}${linktarget}${COLOR_RESET} created."
                        echo ""
                    else
                        if [ -f "${symlink}" ]; then
                            rm "${symlink}" || true
                            ln -s "${linksource}" "${linktarget}" || true
                            echo -e "${COLOR_GREEN}✓${COLOR_RESET} Symlink to file ${COLOR_CYAN}${linksource}${COLOR_RESET} -> ${COLOR_CYAN}${linktarget}${COLOR_RESET} created."
                            echo ""
                        else
                            ln -s "${linksource}" "${linktarget}" || true
                            echo -e "${COLOR_GREEN}✓${COLOR_RESET} New symlink ${COLOR_CYAN}${linksource}${COLOR_RESET} -> ${COLOR_CYAN}${linktarget}${COLOR_RESET} created."
                            echo ""
                        fi
                    fi
                fi
            break;;
            [Nn]* ) 
                echo ""
                # exit;
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# ------------------------------------------------------
# Confirmation prompt
# ------------------------------------------------------
_confirmPrompt() {
    local message="$1"
    while true; do
        read -p "$message (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                echo "Installation started."
            break;;
            [Nn]* ) 
                echo "Installation is Aborted"
                exit;
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}
