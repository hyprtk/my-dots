a#!/usr/bin/env bash
# ==============================================================================
# Unified Arch-based Distribution Installer
# Merges cachyos-branding.sh, unified-apps-installer.sh, and all reference
# files into a single professional setup script.
#
# Supports: arch, archbang, archcraft, archman, bslx, cachyos, endeavouros,
#           garuda, kiro, manjaro, rebornos
# ==============================================================================

set -e  # Exit on error

# ------------------------------------------------------------------------------
# Global Variables
# ------------------------------------------------------------------------------
DISTRO_ID=""
DISTRO_PRETTY_NAME=""
INITRAMFS_TOOL=""
AUR_HELPER=""
DRY_RUN=false

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

print_header() {
    local title="$1"
    echo ""
    echo "================================================================================"
    echo "  $title"
    echo "================================================================================"
    echo ""
}

print_footer() {
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "  Completed: $1"
    echo "--------------------------------------------------------------------------------"
    echo ""
}

print_progress() {
    echo "  ✓ $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run a command with sudo, respecting DRY_RUN
run_sudo() {
    if $DRY_RUN; then
        echo "[DRY RUN] sudo $*"
    else
        sudo "$@"
    fi
}

# Run a command normally, respecting DRY_RUN
run_cmd() {
    if $DRY_RUN; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# Distribution Detection and Branding
# ------------------------------------------------------------------------------

declare -A PRETTY_NAMES=(
    ["arch"]="Hyprtk on (Arch Linux)"
    ["archbang"]="Hyprtk on (ArchBANG Linux)"
    ["archcraft"]="Hyprtk on (Archcraft Linux)"
    ["archman"]="Hyprtk on (Archman Linux)"
    ["bslx"]="Hyprtk on (BlueStar Linux)"
    ["cachyos"]="Hyprtk on (CachyOS)"
    ["endeavouros"]="Hyprtk on (EndeavourOS)"
    ["garuda"]="Hyprtk on (Garuda Linux)"
    ["kiro"]="Hyprtk on (Kiro Linux)"
    ["manjaro"]="Hyprtk on (Manjaro Linux)"
    ["rebornos"]="Hyprtk on (RebornOS Linux)"
)

declare -A SUPPORTED_ALIASES=(
    ["arch"]="arch"
    ["archlinux"]="arch"
    ["archbang"]="archbang"
    ["archcraft"]="archcraft"
    ["archman"]="archman"
    ["bslx"]="bslx"
    ["bluestar"]="bslx"
    ["bluestar linux"]="bslx"
    ["cachyos"]="cachyos"
    ["endeavouros"]="endeavouros"
    ["garuda"]="garuda"
    ["garuda linux"]="garuda"
    ["kiro"]="kiro"
    ["kiro linux"]="kiro"
    ["manjaro"]="manjaro"
    ["manjaro linux"]="manjaro"
    ["rebornos"]="rebornos"
    ["reborn"]="rebornos"
)

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local raw_id="${ID:-}"
        local raw_id_like="${ID_LIKE:-}"
        DISTRO_ID=$(echo "$raw_id" | tr '[:upper:]' '[:lower:]')
    else
        echo "ERROR: /etc/os-release not found. Cannot determine distribution."
        exit 1
    fi

    # Map alias to canonical ID
    local canonical="${SUPPORTED_ALIASES[$DISTRO_ID]}"
    if [ -z "$canonical" ]; then
        # Try ID_LIKE (e.g., ID_LIKE=arch for some)
        for like in $raw_id_like; do
            canonical="${SUPPORTED_ALIASES[$like]}"
            [ -n "$canonical" ] && break
        done
    fi

    if [ -z "$canonical" ]; then
        echo "ERROR: Unsupported distribution: $DISTRO_ID"
        echo "Supported: ${!SUPPORTED_ALIASES[*]}"
        exit 1
    fi

    DISTRO_ID="$canonical"
    DISTRO_PRETTY_NAME="${PRETTY_NAMES[$DISTRO_ID]}"
    if [ -z "$DISTRO_PRETTY_NAME" ]; then
        echo "ERROR: No pretty name defined for $DISTRO_ID"
        exit 1
    fi

    echo "Detected distribution: $DISTRO_ID"
    echo "Pretty name: $DISTRO_PRETTY_NAME"
}

detect_initramfs() {
    if command_exists dracut; then
        INITRAMFS_TOOL="dracut"
    elif command_exists mkinitcpio; then
        INITRAMFS_TOOL="mkinitcpio"
    else
        echo "WARNING: No initramfs tool found (mkinitcpio or dracut)."
        INITRAMFS_TOOL="none"
    fi
    echo "Initramfs tool: $INITRAMFS_TOOL"
}

# ------------------------------------------------------------------------------
# Branding Functions (merged from cachyos-branding.sh)
# ------------------------------------------------------------------------------

update_lsb_release() {
    print_header "Updating /etc/lsb-release"
    if [ -f /etc/lsb-release ]; then
        run_sudo sed -i /etc/lsb-release \
            -e "s|^DISTRIB_ID=.*$|DISTRIB_ID=$DISTRO_ID|" \
            -e "s|^DISTRIB_DESCRIPTION=.*$|DISTRIB_DESCRIPTION=\"$DISTRO_PRETTY_NAME\"|"
        print_progress "lsb-release updated"
    else
        echo "WARNING: /etc/lsb-release not found; skipping."
    fi
}

update_os_release() {
    print_header "Updating /etc/os-release"
    local os_release="/etc/os-release"
    if [ ! -f "$os_release" ]; then
        echo "ERROR: $os_release not found."
        return 1
    fi

    run_sudo sed -i "$os_release" \
        -e "s|^NAME=.*$|NAME=\"$DISTRO_PRETTY_NAME\"|" \
        -e "s|^PRETTY_NAME=.*$|PRETTY_NAME=\"$DISTRO_PRETTY_NAME\"|" \
        -e "s|^ID=.*$|ID=$DISTRO_ID|" \
        -e "s|^ID_LIKE=.*$|ID_LIKE=arch|" \
        -e 's|^ANSI_COLOR=.*$|ANSI_COLOR="38;2;23;147;209"|' \
        -e 's|^HOME_URL=.*$|HOME_URL="https://cachyos.org/"|' \
        -e 's|^DOCUMENTATION_URL=.*$|DOCUMENTATION_URL="https://wiki.cachyos.org/"|' \
        -e 's|^SUPPORT_URL=.*$|SUPPORT_URL="https://discuss.cachyos.org/"|' \
        -e 's|^BUG_REPORT_URL=.*$|BUG_REPORT_URL="https://github.com/cachyos"|' \
        -e 's|^LOGO=.*$|LOGO=cachyos|'

    # add missing ID_LIKE
    if ! grep -q "^ID_LIKE=" "$os_release" && grep -q "^ID=" "$os_release"; then
        run_sudo sed -i "$os_release" -e '/^ID=/a \ID_LIKE=arch'
    fi
    print_progress "os-release updated"
}

update_issues() {
    print_header "Updating /etc/issue"
    if [ -f /etc/issue ]; then
        run_sudo sed -i 's|Arch Linux|CachyOS Linux|g' /etc/issue
        print_progress "issue updated"
    fi
    if [ -f /usr/share/factory/etc/issue ]; then
        run_sudo sed -i 's|Arch Linux|CachyOS Linux|g' /usr/share/factory/etc/issue
        print_progress "factory issue updated"
    fi
}

apply_branding() {
    update_os_release
    update_lsb_release
    update_issues
}

# ------------------------------------------------------------------------------
# Splash Screen Support (adds 'splash' to kernel cmdline and initramfs)
# ------------------------------------------------------------------------------

add_splash() {
    print_header "Adding Splash Screen Support"

    # Ensure plymouth is installed (if not, install it)
    if ! command_exists plymouth; then
        echo "Installing plymouth..."
        run_sudo pacman -S --noconfirm plymouth
    fi

    # Add 'splash' to kernel command line in GRUB
    if [ -f /etc/default/grub ]; then
        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
            # Check if splash is already present
            if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -q "splash"; then
                run_sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' /etc/default/grub
                print_progress "Added 'splash' to GRUB_CMDLINE_LINUX_DEFAULT"
            else
                print_progress "'splash' already present in GRUB_CMDLINE_LINUX_DEFAULT"
            fi
        else
            echo "WARNING: GRUB_CMDLINE_LINUX_DEFAULT not found in /etc/default/grub"
        fi
        # Regenerate GRUB config
        run_sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "WARNING: /etc/default/grub not found; cannot add splash to GRUB"
    fi

    # For mkinitcpio: add 'splash' as a hook if plymouth hook is present
    if [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
        local mkinitcpio_conf="/etc/mkinitcpio.conf"
        if [ -f "$mkinitcpio_conf" ]; then
            # Ensure plymouth hook is in HOOKS
            if grep -q "^HOOKS=" "$mkinitcpio_conf"; then
                if ! grep "^HOOKS=" "$mkinitcpio_conf" | grep -q "plymouth"; then
                    run_sudo sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 plymouth)/' "$mkinitcpio_conf"
                    print_progress "Added 'plymouth' hook to mkinitcpio.conf"
                else
                    print_progress "'plymouth' hook already present in mkinitcpio.conf"
                fi
            else
                echo "WARNING: HOOKS line not found in $mkinitcpio_conf"
            fi
            # Regenerate initramfs
            run_sudo mkinitcpio -P
        fi
    elif [ "$INITRAMFS_TOOL" = "dracut" ]; then
        # For dracut: add 'plymouth' as a module
        local dracut_conf="/etc/dracut.conf.d/10-splash.conf"
        if [ ! -f "$dracut_conf" ]; then
            echo "add_drivers+=\" plymouth \"" | run_sudo tee -a "$dracut_conf"
            print_progress "Added plymouth to dracut configuration"
        else
            if ! grep -q "plymouth" "$dracut_conf"; then
                echo "add_drivers+=\" plymouth \"" | run_sudo tee -a "$dracut_conf"
                print_progress "Added plymouth to dracut configuration"
            else
                print_progress "plymouth already in dracut configuration"
            fi
        fi
        # Regenerate initramfs
        run_sudo dracut --force --regenerate-all
    else
        echo "WARNING: No supported initramfs tool; splash support may be incomplete."
    fi

    print_footer "Splash Screen Setup"
}

# ------------------------------------------------------------------------------
# Root User Configuration
# ------------------------------------------------------------------------------

setup_root_config() {
    print_header "Setting up Root User Configuration"
    if [ -d "$HOME/hyprtk/root" ]; then
        run_sudo cp -r "$HOME/hyprtk/root" /
        print_progress "Copied root configuration from ~/hyprtk/root"
    else
        echo "WARNING: ~/hyprtk/root not found; skipping root config copy."
    fi

    # Add pwfeedback to sudoers (if not already present)
    if ! run_sudo grep -q "pwfeedback" /etc/sudoers; then
        echo 'Defaults env_reset,pwfeedback' | run_sudo tee -a /etc/sudoers
        print_progress "Added pwfeedback to sudoers"
    else
        print_progress "pwfeedback already present in sudoers"
    fi
    print_footer "Root User Configuration"
}

# ------------------------------------------------------------------------------
# AUR Helper Installation
# ------------------------------------------------------------------------------

ensure_aur_helper() {
    if command_exists yay; then
        AUR_HELPER="yay"
    elif command_exists paru; then
        AUR_HELPER="paru"
    else
        echo "No AUR helper (yay/paru) found. Installing yay from source..."
        run_sudo pacman -S --needed --noconfirm base-devel git
        local tmp_dir=$(mktemp -d)
        cd "$tmp_dir"
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        cd /
        rm -rf "$tmp_dir"
        AUR_HELPER="yay"
    fi
    echo "Using AUR helper: $AUR_HELPER"
}

# ------------------------------------------------------------------------------
# Core Installation Sections (adapted from unified-apps-installer.sh)
# ------------------------------------------------------------------------------

install_system() {
    print_header "System Setup"
    echo "Installing core system packages..."

    run_sudo pacman -S --noconfirm \
        sddm \
        blueman \
        pacman-contrib \
        fzf \
        font-manager \
        awesome-terminal-fonts \
        ttf-font-awesome \
        ttf-fira-sans \
        ttf-fira-code \
        ttf-firacode-nerd \
        exa \
        python-pip \
        python-psutil \
        python-rich \
        python-click \
        xdg-desktop-portal-gtk \
        xdg-user-dirs \
        xdg-user-dirs-gtk \
        os-prober \
        polkit-gnome \
        gnome-keyring \
        pcp \
        pcp-gui \
        gtk4-layer-shell \
        hyprpicker

    run_sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm 2>/dev/null || true

    ensure_aur_helper

    local aur_pkgs=(
        bibata-cursor-theme
        trizen
        sublime-text-4
        sddm-theme-sugar-candy-git
        pacseek
    )

    if [[ "$DISTRO_ID" != "rebornos" ]]; then
        aur_pkgs+=(pamac-all libpamac-full pamac-cli)
    fi

    $AUR_HELPER -S "${aur_pkgs[@]}" --noconfirm

    # Papirus Folders
    echo "Installing Papirus Folders..."
    wget -qO- https://git.io/papirus-folders-install | env PREFIX="$HOME/.local" sh

    print_footer "System Setup"
}

install_graphics() {
    print_header "Graphics Card Setup"
    echo "Select your graphics card:"
    echo "1) Intel"
    echo "2) AMD"
    echo "3) Nvidia"
    echo "Defaults to AMD if no valid choice."
    read -r -p "Enter choice [1-3]: " choice

    ensure_aur_helper

    case $choice in
        1)
            run_sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
            ;;
        2)
            run_sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            add_module_to_initramfs "amdgpu"
            ;;
        3)
            # Nvidia: assumes GRUB
            run_sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub
            run_sudo grub-mkconfig -o /boot/grub/grub.cfg

            for mod in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
                add_module_to_initramfs "$mod"
            done

            echo -e "options nvidia-drm modeset=1" | run_sudo tee -a /etc/modprobe.d/nvidia.conf

            run_sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
            $AUR_HELPER -S --noconfirm libva-nvidia-driver-git
            ;;
        *)
            # Default AMD
            run_sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            add_module_to_initramfs "amdgpu"
            ;;
    esac

    print_footer "Graphics Card Setup"
}

add_module_to_initramfs() {
    local module="$1"
    if [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
        if grep -q "^MODULES=.*$module" /etc/mkinitcpio.conf; then
            echo "Module $module already in mkinitcpio.conf."
        else
            run_sudo sed -i "s/^MODULES=()/MODULES=($module)/" /etc/mkinitcpio.conf
            echo "Added $module to MODULES in mkinitcpio.conf."
        fi
        run_sudo mkinitcpio -P
    elif [ "$INITRAMFS_TOOL" = "dracut" ]; then
        local conf_file="/etc/dracut.conf.d/10-$module.conf"
        if [ ! -d /etc/dracut.conf.d ]; then
            run_sudo mkdir -p /etc/dracut.conf.d
        fi
        if ! grep -q "add_drivers+=\" $module \"" "$conf_file" 2>/dev/null; then
            echo "add_drivers+=\" $module \"" | run_sudo tee -a "$conf_file"
            echo "Added $module to dracut."
        else
            echo "Module $module already in dracut configuration."
        fi
        run_sudo dracut --force --regenerate-all
    else
        echo "WARNING: No initramfs tool configured. Skipping module addition."
    fi
}

install_network() {
    print_header "Network and Filesystem Packages"
    run_sudo pacman -S --noconfirm \
        networkmanager \
        network-manager-applet \
        git \
        freerdp \
        curl \
        gvfs \
        gvfs-afc \
        gvfs-dnssd \
        gvfs-goa \
        gvfs-gphoto2 \
        gvfs-mtp \
        gvfs-nfs \
        gvfs-onedrive \
        gvfs-smb \
        gvfs-wsdd \
        ntfs-3g \
        samba
    print_footer "Network and Filesystem Packages"
}

install_media() {
    print_header "Media Packages"
    run_sudo pacman -S --noconfirm \
        xclip \
        pamixer \
        wf-recorder \
        pavucontrol \
        tumbler \
        vlc \
        mpv \
        ffmpeg
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm hyprquickframe-git
    print_footer "Media Packages"
}

install_printers() {
    print_header "Printer Packages"
    run_sudo pacman -S --noconfirm \
        cups \
        cups-pdf \
        cups-filters \
        nss-mdns \
        system-config-printer \
        cups-browsed \
        libusb \
        ipp-usb \
        xdg-utils \
        colord \
        logrotate
    run_sudo systemctl enable --now cups
    print_footer "Printer Packages"
}

install_filetools() {
    print_header "File Tools"
    run_sudo pacman -S --noconfirm thunar mousepad
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm thunar-shares-plugin
    print_footer "File Tools"
}

install_terminal_tools() {
    print_header "Terminal Tools"
    run_sudo pacman -S --noconfirm \
        eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm fastfetch
    print_footer "Terminal Tools"
}

install_system_tools() {
    print_header "System Tools"
    run_sudo pacman -S --noconfirm \
        timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm gnome-disk-utility
    print_footer "System Tools"
}

install_web_tools() {
    print_header "Web Tools"
    run_sudo pacman -S --noconfirm chromium
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm brave-bin github-desktop-bin
    print_footer "Web Tools"
}

install_fonts() {
    print_header "Fonts Installation"
    local repo_url="https://github.com/hyprtk/fonts.git"
    local user_font_dir="$HOME/.local/share/fonts"

    read -p "Install fonts to user directory (Y) or system-wide (N)? (Yy/Nn): " yn
    if [[ $yn =~ [Yy] ]]; then
        if [ -d "$user_font_dir" ]; then
            read -p "Overwrite with fresh clone? (y/n): " overwrite
            if [[ $overwrite =~ [Yy] ]]; then
                rm -rf "$user_font_dir"
                git clone "$repo_url" "$user_font_dir"
            else
                echo "Keeping existing fonts."
            fi
        else
            mkdir -p "$user_font_dir"
            git clone "$repo_url" "$user_font_dir"
        fi
        echo "User fonts installed."
    else
        local tmp_dir=$(mktemp -d)
        git clone "$repo_url" "$tmp_dir"
        run_sudo cp -r "$tmp_dir"/* /usr/share/fonts/
        run_sudo fc-cache -fv
        rm -rf "$tmp_dir"
        echo "System fonts installed."
    fi
    print_footer "Fonts Installation"
}

install_wallpapers() {
    print_header "Wallpapers Installation"
    read -p "Do you want to clone the wallpapers from hyprtk? If not, default wallpapers will be copied. (Yy/Nn): " yn
    local wall_dir="$HOME/Pictures/Wallpapers"
    mkdir -p "$wall_dir"
    if [[ $yn =~ [Yy] ]]; then
        if [ -d "$wall_dir/.git" ]; then
            echo "Wallpaper repository already exists; updating..."
            cd "$wall_dir" && git pull
        else
            rm -rf "$wall_dir"
            git clone https://github.com/hyprtk/wallpaper.git "$wall_dir"
        fi
        echo "Wallpapers cloned."
    else
        if [ -d "$HOME/hyprtk/Wallpapers" ]; then
            cp "$HOME/hyprtk/Wallpapers"/* "$wall_dir/"
            echo "Default wallpapers copied."
        else
            echo "No default wallpapers found in ~/hyprtk/Wallpapers. Skipping."
        fi
    fi
    print_footer "Wallpapers Installation"
}

install_xfce4() {
    print_header "XFCE4 Desktop Environment"
    run_sudo pacman -S --noconfirm xfce4 xfce4-goodies parole
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm tumbler-extra-thumbnailers
    print_footer "XFCE4 Installation"
}

install_hyprland() {
    print_header "Hyprland and Related Packages"
    run_sudo pacman -S --noconfirm \
        hyprland \
        xdg-desktop-portal-wlr \
        swayidle \
        swappy \
        cliphist \
        xorg-xhost \
        nwg-look \
        mission-center \
        curl \
        imagemagick \
        jq \
        bc \
        brightnessctl \
        playerctl \
        libadwaita \
        gtk-layer-shell \
        python \
        python-pip \
        python-virtualenv \
        python-gobject \
        gtk4 \
        wob

    ensure_aur_helper
    $AUR_HELPER -S --noconfirm \
        awww \
        swaylock-effects \
        gvfs-afc \
        gvfs-goa \
        gvfs-gphoto2 \
        gvfs-mtp \
        gvfs-nfs \
        gvfs-smb \
        7zip \
        unzip \
        unrar \
        waybar-git

    print_footer "Hyprland Installation"
}

install_hyprviz() {
    print_header "HyprViz (Hyprland Configuration Tool)"
    local install_dir="$HOME/Downloads/yay-git/src"
    mkdir -p "$install_dir"
    cd "$install_dir"
    if [ -d "hyprviz-bin" ]; then
        cd hyprviz-bin && git pull
    else
        git clone https://aur.archlinux.org/hyprviz-bin.git
        cd hyprviz-bin
    fi
    makepkg -si --noconfirm
    print_footer "HyprViz Installation"
}

install_matuwall() {
    print_header "Matuwall Wallpaper Picker"
    local repo_dir="$HOME/.local/share/Matuwall"
    if [ -d "$repo_dir" ]; then
        cd "$repo_dir" && git pull
    else
        git clone https://github.com/naurissteins/Matuwall.git "$repo_dir"
        cd "$repo_dir"
    fi
    python3 -m venv --system-site-packages .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install .
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(pwd)/.venv/bin/matuwall" "$HOME/.local/bin/matuwall"
    print_footer "Matuwall Installation"
}

install_3dprinting() {
    print_header "3D Printing Software"
    ensure_aur_helper
    $AUR_HELPER -S --noconfirm orca-slicer-bin bambustudio-bin
    print_footer "3D Printing Software"
}

install_sddm() {
    print_header "SDDM Display Manager"
    run_sudo pacman -S --noconfirm sddm

    local dms=("lightdm" "gdm" "lxdm" "slim" "kdm" "ly")
    for dm in "${dms[@]}"; do
        run_sudo systemctl disable "$dm" 2>/dev/null || true
        run_sudo systemctl disable "${dm}-plymouth" 2>/dev/null || true
    done

    run_sudo systemctl enable sddm --force

    local config_dir="/etc/sddm.conf.d"
    local config_file="$HOME/hyprtk/sddm/sddm.conf"
    run_sudo mkdir -p "$config_dir"
    if [ -f "$config_file" ]; then
        run_sudo cp "$config_file" "$config_dir/"
        echo "Custom SDDM config copied."
    else
        echo "No custom SDDM config found at $config_file. Skipping."
    fi

    print_footer "SDDM Installation"
}

install_sddm_grub_theming() {
    print_header "SDDM and GRUB Theming"
    local source_sddm_conf="$HOME/hyprtk/sddm/sddm.conf"
    local source_theme_conf="$HOME/hyprtk/sddm/theme.conf"
    local source_wallpaper="$HOME/hyprtk/default.png"
    local sddm_theme_dir="/usr/share/sddm/themes/Sugar-Candy"

    if [ ! -f "$source_sddm_conf" ] || [ ! -f "$source_theme_conf" ] || [ ! -f "$source_wallpaper" ]; then
        echo "Warning: Missing required theme files in ~/hyprtk/sddm/ or ~/hyprtk/default.png"
        echo "Skipping SDDM/GRUB theming."
        print_footer "SDDM and GRUB Theming (skipped)"
        return
    fi

    if [ ! -d "$sddm_theme_dir" ]; then
        echo "Error: SDDM theme Sugar-Candy not found at $sddm_theme_dir"
        echo "Please install sddm-theme-sugar-candy-git first."
        print_footer "SDDM and GRUB Theming (failed)"
        return
    fi

    run_sudo mkdir -p /etc/sddm.conf.d
    run_sudo cp "$source_sddm_conf" /etc/sddm.conf.d/

    cp "$source_wallpaper" ~/.cache/current-wallpaper.png
    run_sudo cp ~/.cache/current-wallpaper.png "$sddm_theme_dir/Backgrounds/"
    run_sudo cp "$source_theme_conf" "$sddm_theme_dir/"

    run_sudo rm -rf /usr/share/grub/themes/* /boot/grub/themes/*
    run_sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    run_sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    run_sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    run_sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    run_sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | run_sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | run_sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | run_sudo tee -a /etc/default/grub
    run_sudo grub-mkconfig -o /boot/grub/grub.cfg
    run_sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

    print_footer "SDDM and GRUB Theming"
}

# ------------------------------------------------------------------------------
# View-Only Menu (shows actions without executing)
# ------------------------------------------------------------------------------

show_action_summary() {
    echo ""
    echo "========================================================================"
    echo "  ACTION SUMMARY (DRY RUN)"
    echo "========================================================================"
    echo "Distribution: $DISTRO_ID"
    echo "Pretty Name:  $DISTRO_PRETTY_NAME"
    echo "Initramfs:    $INITRAMFS_TOOL"
    echo "AUR Helper:   $AUR_HELPER"
    echo ""
    echo "The following actions will be performed:"
    echo "  - Update /etc/os-release and /etc/lsb-release with the pretty name"
    echo "  - Update /etc/issue (replace Arch with CachyOS style)"
    echo "  - Add splash screen support (plymouth, kernel parameter, initramfs hooks)"
    echo "  - Copy root configuration from ~/hyprtk/root to /"
    echo "  - Install selected packages (based on menu options)"
    echo ""
    echo "NOTE: This is a summary only. To execute, remove the --dry-run flag."
    echo "========================================================================"
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------

main_menu() {
    echo ""
    echo "========================================================================"
    echo "  Unified Arch-based Distribution Installer"
    echo "========================================================================"
    echo "  Detected Distribution: $DISTRO_ID"
    echo "  Pretty Name:           $DISTRO_PRETTY_NAME"
    echo "  Initramfs Tool:        $INITRAMFS_TOOL"
    echo "  DRY RUN:               $DRY_RUN"
    echo ""
    echo "  Select installation options:"
    echo "  1) Install Everything (all sections)"
    echo "  2) Core System (system, graphics, network, media, printers)"
    echo "  3) Desktop Environments (XFCE4, Hyprland, HyprViz)"
    echo "  4) Additional Tools (file, terminal, system, web, fonts, wallpapers)"
    echo "  5) 3D Printing & Matuwall"
    echo "  6) SDDM & GRUB Configuration"
    echo "  7) Apply Branding Only (update os-release/lsb-release/issue)"
    echo "  8) Setup Splash Screen"
    echo "  9) Setup Root Configuration"
    echo " 10) Show Summary (view-only actions)"
    echo " 11) Exit"
    echo ""
    read -r -p "Enter choice [1-11]: " choice

    case $choice in
        1)
            install_system
            install_graphics
            install_network
            install_media
            install_printers
            install_filetools
            install_terminal_tools
            install_system_tools
            install_web_tools
            install_fonts
            install_wallpapers
            install_xfce4
            install_hyprland
            install_hyprviz
            install_matuwall
            install_3dprinting
            install_sddm
            install_sddm_grub_theming
            apply_branding
            add_splash
            setup_root_config
            ;;
        2)
            install_system
            install_graphics
            install_network
            install_media
            install_printers
            ;;
        3)
            install_xfce4
            install_hyprland
            install_hyprviz
            ;;
        4)
            install_filetools
            install_terminal_tools
            install_system_tools
            install_web_tools
            install_fonts
            install_wallpapers
            ;;
        5)
            install_3dprinting
            install_matuwall
            ;;
        6)
            install_sddm
            install_sddm_grub_theming
            ;;
        7)
            apply_branding
            ;;
        8)
            add_splash
            ;;
        9)
            setup_root_config
            ;;
        10)
            show_action_summary
            ;;
        11)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "This script should not be run as root. It uses sudo when needed."
    exit 1
fi

# Check for --dry-run flag
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

detect_distro
detect_initramfs

if ! command_exists pacman; then
    echo "ERROR: pacman not found. This script is for Arch-based systems."
    exit 1
fi

ensure_aur_helper

if $DRY_RUN; then
    show_action_summary
    exit 0
fi

main_menu

echo ""
echo "========================================================================"
echo "  Installation process completed."
echo "========================================================================"