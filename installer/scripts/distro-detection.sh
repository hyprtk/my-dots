#!/bin/bash
# Distro detection script
# Detects the current Arch-based distribution

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"

# Detect the current distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            arch)
                echo "arch"
                ;;
            garuda)
                echo "garuda"
                ;;
            cachyos)
                echo "cachyos"
                ;;
            manjaro)
                echo "manjaro"
                ;;
            endeavouros)
                echo "endeavour"
                ;;
            archcraft)
                echo "archcraft"
                ;;
            archman)
                echo "archman"
                ;;
            archbang)
                echo "archbang"
                ;;
            bslx)
                echo "bslx"
                ;;
            kiro)
                echo "kiro"
                ;;
            reborn)
                echo "reborn"
                ;;
            *)
                # Try to detect based on other files
                if [ -f /etc/arch-release ]; then
                    echo "arch"
                else
                    echo "unknown"
                fi
                ;;
        esac
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Get distro display name
get_distro_name() {
    local distro="$1"
    case $distro in
        "arch")
            echo "Arch Linux"
            ;;
        "garuda")
            echo "Garuda Linux"
            ;;
        "cachyos")
            echo "CachyOS"
            ;;
        "manjaro")
            echo "Manjaro Linux"
            ;;
        "endeavour")
            echo "EndeavourOS"
            ;;
        "archcraft")
            echo "Archcraft"
            ;;
        "archman")
            echo "Archman"
            ;;
        "archbang")
            echo "ArchBang"
            ;;
        "bslx")
            echo "BSLX"
            ;;
        "kiro")
            echo "Kiro"
            ;;
        "reborn")
            echo "RebornOS"
            ;;
        *)
            echo "Unknown Distro"
            ;;
    esac
}

# Check if distro is supported
is_supported_distro() {
    local distro="$1"
    case $distro in
        "arch"|"garuda"|"cachyos"|"manjaro"|"endeavour"|"archcraft"|"archman"|"archbang"|"bslx"|"kiro"|"reborn")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if package is installed
_is_package_installed() {
    local package="$1"
    if pacman -Qs "^${package}$" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Remove packages if installed
_remove_if_installed() {
    local packages=("$@")
    local to_remove=()
    
    for pkg in "${packages[@]}"; do
        if _is_package_installed "$pkg"; then
            to_remove+=("$pkg")
        fi
    done
    
    if [ ${#to_remove[@]} -gt 0 ]; then
        sudo pacman -Rns "${to_remove[@]}" --noconfirm 2>/dev/null || true
    fi
}

# Remove packages if installed (with -Rcs flag)
_remove_if_installed_rcs() {
    local packages=("$@")
    local to_remove=()
    
    for pkg in "${packages[@]}"; do
        if _is_package_installed "$pkg"; then
            to_remove+=("$pkg")
        fi
    done
    
    if [ ${#to_remove[@]} -gt 0 ]; then
        sudo pacman -Rcs "${to_remove[@]}" --noconfirm 2>/dev/null || true
    fi
}

# Remove AUR packages if installed
_remove_aur_if_installed() {
    local packages=("$@")
    local to_remove=()
    
    for pkg in "${packages[@]}"; do
        if yay -Qs "^${pkg}$" > /dev/null 2>&1; then
            to_remove+=("$pkg")
        fi
    done
    
    if [ ${#to_remove[@]} -gt 0 ]; then
        yay -Rns "${to_remove[@]}" --noconfirm 2>/dev/null || true
    fi
}

# Get distro-specific package removal command
get_distro_removal_command() {
    local distro="$1"
    case $distro in
        "archbang")
            _remove_if_installed "plasma-meta" "kde-applications-meta" "plasma" "kde-applications" "swaylock"
            ;;
        "bslx")
            _remove_if_installed_rcs "plasma-meta" "kde-applications-meta" "plasma" "kde-applications"
            ;;
        "kiro")
            _remove_if_installed "plasma-meta" "kde-applications-meta" "plasma" "kde-applications" "xfce4" "xfce4-goodies" "thunar" "catfish" "thunar-shares-plugin"
            _remove_aur_if_installed "sddm-git" "fastfetch-git"
            ;;
        *)
            _remove_if_installed "plasma-meta" "kde-applications-meta" "plasma" "kde-applications"
            ;;
    esac
}

# Check if distro needs hypr config backup
needs_hypr_backup() {
    local distro="$1"
    case $distro in
        "garuda"|"cachyos"|"archcraft"|"archman"|"archbang"|"bslx"|"kiro"|"reborn"|"endeavour")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if distro has cachyos branding
has_cachyos_branding() {
    local distro="$1"
    case $distro in
        "cachyos")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if distro needs grub wallpaper
needs_grub_wallpaper() {
    local distro="$1"
    case $distro in
        "bslx")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if distro needs grudupdater
needs_grudupdater() {
    local distro="$1"
    case $distro in
        "kiro")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if distro uses different pywal wallpaper path
uses_cache_wallpaper() {
    local distro="$1"
    case $distro in
        "archcraft")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get initramfs type for distro (dynamic detection)
get_initramfs_type() {
    # Check if dracut is installed
    if command -v dracut > /dev/null 2>&1; then
        echo "dracut"
    # Check if mkinitcpio is installed
    elif command -v mkinitcpio > /dev/null 2>&1; then
        echo "mkinitcpio"
    # Default to mkinitcpio for Arch-based distros
    else
        echo "mkinitcpio"
    fi
}

# Update initramfs based on detected type
update_initramfs() {
    local initramfs_type=$(get_initramfs_type)
    
    case $initramfs_type in
        "dracut")
            sudo dracut --force --regenerate-all
            ;;
        "mkinitcpio")
            sudo mkinitcpio -P
            ;;
        *)
            sudo mkinitcpio -P
            ;;
    esac
}

# Update initramfs with specific config
update_initramfs_config() {
    local config="$1"
    local output="$2"
    local initramfs_type=$(get_initramfs_type)
    
    case $initramfs_type in
        "dracut")
            if [ -n "$output" ]; then
                sudo dracut --force "$output" || true
            else
                sudo dracut --force || true
            fi
            ;;
        "mkinitcpio")
            if [ -n "$config" ] && [ -n "$output" ]; then
                sudo mkinitcpio --config "$config" --generate "$output" || true
            else
                sudo mkinitcpio -P || true
            fi
            ;;
        *)
            if [ -n "$config" ] && [ -n "$output" ]; then
                sudo mkinitcpio --config "$config" --generate "$output" || true
            else
                sudo mkinitcpio -P || true
            fi
            ;;
    esac
}
