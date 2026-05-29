#!/bin/bash

# =============================================================================
# Unified Zenity GUI Installer for Hyprtk Arch Linux (Hyprland & XFCE)
# =============================================================================

set -e  # Exit on error, but we'll catch errors gracefully

# -----------------------------------------------------------------------------
# 0. Helper functions and initial setup
# -----------------------------------------------------------------------------

# Detect initramfs builder (dracut-rebuild, dracut, or mkinitcpio)
detect_initramfs_builder() {
    if command -v dracut-rebuild &>/dev/null; then
        echo "dracut-rebuild"
    elif command -v dracut &>/dev/null && [ -f /etc/dracut.conf.d/* ] 2>/dev/null; then
        echo "dracut"
    elif command -v mkinitcpio &>/dev/null; then
        echo "mkinitcpio"
    else
        echo "unknown"
    fi
}

# Run dracut rebuild using the appropriate command (dracut-rebuild or dracut)
run_dracut_rebuild() {
    if command -v dracut-rebuild &>/dev/null; then
        sudo -A dracut-rebuild --regenerate-all --force
    else
        sudo -A dracut --regenerate-all --force
    fi
}

# Remove ~/.config/hypr symlink/directory forcefully
remove_hypr_config() {
    echo "Removing ~/.config/hypr symlink/directory..."
    if [[ -L "$HOME/.config/hypr" ]] || [[ -e "$HOME/.config/hypr" ]]; then
        rm -rf "$HOME/.config/hypr"
        echo "Removed."
    else
        echo "~/.config/hypr does not exist."
    fi
}

# Cleanup on exit
cleanup() {
    rm -f "$ASKPASS_SCRIPT"
}
trap cleanup EXIT

# Ensure required commands exist
for cmd in zenity pacman yay git; do
    if ! command -v "$cmd" &>/dev/null; then
        if [[ "$cmd" == "zenity" ]]; then
            echo "Zenity not found. Installing via pacman (requires sudo) ..."
            sudo pacman -S --noconfirm zenity
        elif [[ "$cmd" == "yay" ]]; then
            echo "yay not found. Will be installed later."
        else
            echo "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    fi
done

# -----------------------------------------------------------------------------
# 1. Password handling (askpass)
# -----------------------------------------------------------------------------
PASSWORD=$(zenity --password --title="Authentication Required" --text="Enter your sudo password to begin installation:" --width=400)

if [ -z "$PASSWORD" ]; then
    zenity --error --text="Password cannot be empty. Exiting."
    exit 1
fi

ASKPASS_SCRIPT=$(mktemp /tmp/askpass.XXXXXX.sh)
echo '#!/bin/bash' > "$ASKPASS_SCRIPT"
echo "echo '$PASSWORD'" >> "$ASKPASS_SCRIPT"
chmod +x "$ASKPASS_SCRIPT"

export SUDO_ASKPASS="$ASKPASS_SCRIPT"
export NEED_SUDO=1

# Validate password
if ! sudo -A true 2>/dev/null; then
    zenity --error --text="Incorrect password. Exiting."
    exit 1
fi

# Wrapper for pacman (requires sudo -A)
run_pacman() {
    sudo -A pacman --noconfirm "$@"
}

# Wrapper for yay (does NOT use sudo)
run_yay() {
    yay --noconfirm "$@"
}

# Helper to ask for a fresh root password (returns password via stdout)
ask_root_password() {
    local msg="${1:-Please enter your root password:}"
    zenity --password --title="Root Authentication" --text="$msg" --width=400
}

# -----------------------------------------------------------------------------
# 2. Pre‑installation cleanup: remove KDE/GNOME packages & other DMs
# -----------------------------------------------------------------------------

remove_kde_gnome() {
    echo "Checking for installed KDE and GNOME packages..."
    
    # Groups to remove entirely
    local groups_to_remove=("plasma" "kde-applications" "gnome" "gnome-extra")
    local pkgs_to_remove=()
    
    # Collect packages from groups
    for grp in "${groups_to_remove[@]}"; do
        if pacman -Qg "$grp" &>/dev/null; then
            mapfile -t grp_pkgs < <(pacman -Qg "$grp" | cut -d' ' -f2)
            pkgs_to_remove+=("${grp_pkgs[@]}")
        fi
    done
    
    # Also remove any package whose name contains 'kde' or 'gnome' (except sddm)
    mapfile -t name_pkgs < <(pacman -Qq 2>/dev/null | grep -E '(kde|gnome)' | grep -v 'sddm' || true)
    pkgs_to_remove+=("${name_pkgs[@]}")
    
    # Remove duplicates
    if [[ ${#pkgs_to_remove[@]} -gt 0 ]]; then
        local unique_pkgs=($(printf "%s\n" "${pkgs_to_remove[@]}" | sort -u))
        echo "The following KDE/GNOME packages will be removed:"
        printf '  %s\n' "${unique_pkgs[@]}"
        
        # Use pacman to remove them (--noconfirm, but we also need to handle deps)
        # Convert to space-separated list
        local pkg_list="${unique_pkgs[*]}"
        if ! sudo -A pacman -Rns --noconfirm $pkg_list 2>/dev/null; then
            echo "Warning: Some packages could not be removed (maybe dependencies)."
        fi
    else
        echo "No KDE/GNOME packages found."
    fi
}

disable_other_dms_and_enable_sddm() {
    echo "Disabling other display managers (LightDM, GDM, LXDM, SLiM, KDM, Ly)..."
    
    # List of DMs and their Plymouth counterparts
    local dms=("lightdm" "gdm" "lxdm" "slim" "kdm" "ly")
    for dm in "${dms[@]}"; do
        sudo -A systemctl disable "$dm" 2>/dev/null || true
        sudo -A systemctl disable "${dm}-plymouth" 2>/dev/null || true
    done
    
    echo "Ensuring SDDM is installed..."
    if ! pacman -Qs sddm >/dev/null; then
        run_pacman -S sddm
    fi
    
    echo "Enabling SDDM as the default display manager..."
    sudo -A systemctl enable sddm
    sudo -A systemctl enable sddm --force   # Override any conflicts
    echo "SDDM enabled."
}

# -----------------------------------------------------------------------------
# 3. Load library functions (modified for silent/fast operation)
# -----------------------------------------------------------------------------
# Source the library.sh but override the interactive symlink function
LIBRARY_PATH="$(dirname "$0")/scripts/library.sh"
if [[ ! -f "$LIBRARY_PATH" ]]; then
    LIBRARY_PATH=~/hyprtk/scripts/library.sh
fi
if [[ -f "$LIBRARY_PATH" ]]; then
    source "$LIBRARY_PATH"
else
    # Define minimal required functions if library not found
    _isInstalledPacman() {
        pacman -Qs "$1" | grep -q "local.*$1"
    }
    _isInstalledYay() {
        yay -Qs "$1" | grep -q "local.*$1"
    }
    _installPackagesPacman() {
        local toInstall=()
        for pkg in "$@"; do
            if ! _isInstalledPacman "$pkg"; then
                toInstall+=("$pkg")
            fi
        done
        if [[ ${#toInstall[@]} -gt 0 ]]; then
            run_pacman -S "${toInstall[@]}"
        fi
    }
    _installPackagesYay() {
        local toInstall=()
        for pkg in "$@"; do
            if ! _isInstalledYay "$pkg"; then
                toInstall+=("$pkg")
            fi
        done
        if [[ ${#toInstall[@]} -gt 0 ]]; then
            run_yay -S "${toInstall[@]}"
        fi
    }
fi

# Force symlink creation without user prompt
_forceSymLink() {
    local name="$1"
    local symlink="$2"
    local linksource="$3"
    local linktarget="$4"

    # Remove existing file/directory/symlink
    if [[ -L "$symlink" ]] || [[ -e "$symlink" ]]; then
        rm -rf "$symlink"
    fi
    # Create parent directory if needed
    mkdir -p "$(dirname "$symlink")"
    ln -s "$linksource" "$linktarget" 2>/dev/null || ln -s "$linksource" "$symlink"
    echo "Symlink created: $linksource -> $linktarget"
}

# -----------------------------------------------------------------------------
# 4. Component installation functions (derived from original scripts)
# -----------------------------------------------------------------------------

install_yay() {
    if command -v yay &>/dev/null; then
        echo "yay already installed."
        return
    fi
    echo "Installing yay..."
    run_pacman -S "base-devel"
    git clone https://aur.archlinux.org/yay-git.git /tmp/yay-git
    pushd /tmp/yay-git >/dev/null
    
    # Ask for root password to install via makepkg -si (which calls pacman -U)
    ROOT_PASSWORD=$(ask_root_password "yay installation requires root privileges to install the package.\nPlease enter your root password:")
    if [[ -z "$ROOT_PASSWORD" ]]; then
        echo "Root password not provided. Skipping yay installation."
        popd >/dev/null
        return 1
    fi
    ROOT_ASKPASS=$(mktemp /tmp/root_askpass.XXXXXX.sh)
    echo '#!/bin/bash' > "$ROOT_ASKPASS"
    echo "echo '$ROOT_PASSWORD'" >> "$ROOT_ASKPASS"
    chmod +x "$ROOT_ASKPASS"
    export SUDO_ASKPASS="$ROOT_ASKPASS"
    makepkg -si --noconfirm
    rm -f "$ROOT_ASKPASS"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"  # Restore original
    
    popd >/dev/null
    rm -rf /tmp/yay-git
}

install_chaotic_aur() {
    echo "Enabling Chaotic AUR..."
    if [[ -f ~/hyprtk/hypr/packages/chaotic_aur.sh ]]; then
        sudo -A bash ~/hyprtk/hypr/packages/chaotic_aur.sh --install
    else
        echo "chaotic_aur.sh not found, skipping."
    fi
}

install_graphics_card() {
    local choice
    local initramfs_builder=$(detect_initramfs_builder)
    
    choice=$(zenity --list --radiolist --title="Graphics Card Driver" \
        --column="Pick" --column="GPU Type" \
        FALSE "Intel" TRUE "AMD (Default)" FALSE "Nvidia" FALSE "Virtualization (QEMU/virt & VMware)" \
        --width=400 --height=300)
    
    case "$choice" in
        Intel)
            run_pacman -S xf86-video-intel mesa vulkan-intel
            if [ "$initramfs_builder" = "mkinitcpio" ]; then
                sudo -A mkinitcpio -P
            elif [[ "$initramfs_builder" =~ dracut ]]; then
                run_dracut_rebuild
            fi
            ;;
        Nvidia)
            sudo -A sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub
            sudo -A grub-mkconfig -o /boot/grub/grub.cfg
            if [ "$initramfs_builder" = "mkinitcpio" ]; then
                sudo -A sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
                echo "options nvidia-drm modeset=1" | sudo -A tee -a /etc/modprobe.d/nvidia.conf
                run_pacman -S nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
                run_yay -S libva-nvidia-driver-git
                sudo -A mkinitcpio -P
            elif [[ "$initramfs_builder" =~ dracut ]]; then
                echo "options nvidia-drm modeset=1" | sudo -A tee -a /etc/modprobe.d/nvidia.conf
                sudo -A cp -r ~/hyprtk/dracut/nvidia.conf /etc/dracut.conf.d
                sudo -A cp -r ~/hyprtk/nvidia/grub /etc/default
                run_pacman -S nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
                run_yay -S libva-nvidia-driver-git
                run_dracut_rebuild
            fi
            ;;
        Virtualization*)
            echo "Installing virtualization guest drivers (QEMU/virt & VMware)..."
            run_pacman -S qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools 
            run_yay -S xf86-video-vmware
            # Enable services
            sudo -A systemctl enable --now qemu-guest-agent 2>/dev/null || true
            sudo -A systemctl enable --now spice-vdagentd 2>/dev/null || true
            sudo -A systemctl enable --now vmtoolsd 2>/dev/null || true
            echo "Virtualization drivers installed. For 3D acceleration, ensure VM supports virgl (QEMU) or 3D acceleration (VMware)."
            ;;
        AMD|*)
            run_pacman -S xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            if [ "$initramfs_builder" = "mkinitcpio" ]; then
                sudo -A sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
                sudo -A mkinitcpio -P
            elif [[ "$initramfs_builder" =~ dracut ]]; then
                run_dracut_rebuild
            fi
            ;;
    esac
}

install_hyprland() {
    echo "Installing Hyprland and core components..."
    run_pacman -S hyprland xdg-desktop-portal-wlr waybar swayidle swappy cliphist \
        xorg-xhost nwg-look mission-center curl imagemagick jq bc brightnessctl \
        playerctl libadwaita gtk-layer-shell python python-pip python-virtualenv \
        python-gobject gtk4 wob
    run_yay -S awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp \
        gvfs-nfs gvfs-smb 7zip unzip unrar
}

install_xfce4() {
    echo "Installing XFCE4 desktop..."
    run_pacman -S xfce4 xfce4-goodies parole
    run_yay -S tumbler-extra-thumbnailers
}

install_filetools() {
    echo "Installing file tools..."
    run_pacman -S thunar mousepad
    run_yay -S thunar-shares-plugin
}

install_webtools() {
    echo "Installing web tools..."
    run_pacman -S chromium
    run_yay -S brave-bin github-desktop-bin
}

install_printers() {
    echo "Installing printer support..."
    run_yay -S cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed \
        libusb ipp-usb xdg-utils colord logrotate
    sudo -A systemctl enable --now cups
}

install_network() {
    echo "Installing network tools..."
    run_pacman -S networkmanager network-manager-applet git freerdp curl gvfs \
        gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive \
        gvfs-smb gvfs-wsdd ntfs-3g samba
    sudo -A systemctl enable --now NetworkManager
}

install_media() {
    echo "Installing media packages..."
    run_pacman -S xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg
    run_yay -S hyprquickframe-git
}

install_terminaltools() {
    echo "Installing terminal tools..."
    run_pacman -S eza micro xfce4-terminal btop alacritty kitty starship ranger nano figlet neovim
    run_yay -S fastfetch
}

install_systemtools() {
    echo "Installing system tools..."
    run_pacman -S timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit
    run_yay -S gnome-disk-utility
    sudo -A systemctl enable --now cockpit.socket
}

install_system() {
    echo "Installing system packages (SDDM, bluetooth, etc.)..."
    run_pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts \
        ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip \
        python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs \
        xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker
    run_pacman -S $(pacman -Ssq 'pcp-pmda-*') 2>/dev/null || true
    # Install pamac packages with existence check (already handled by _installPackagesYay)
    _installPackagesYay pamac-all libpamac-full pamac-cli
    run_yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek
    # Enable services
    sudo -A systemctl enable bluetooth sddm
}

install_hyprviz() {
    echo "Installing HyprViz (Hyprland configuration tool)..."
    
    # Clean previous builds
    rm -rf /tmp/hyprviz-bin
    git clone https://aur.archlinux.org/hyprviz-bin.git /tmp/hyprviz-bin
    pushd /tmp/hyprviz-bin >/dev/null
    
    # Build as normal user (no sudo)
    echo "Building HyprViz as user..."
    makepkg -s --noconfirm
    
    # Find the generated package file
    PKG_FILE=$(ls *.pkg.tar.zst 2>/dev/null | head -n1)
    if [[ -z "$PKG_FILE" ]]; then
        echo "Error: Failed to build HyprViz package."
        popd >/dev/null
        return 1
    fi
    
    # Ask for root password to install the package
    ROOT_PASSWORD=$(ask_root_password "Installing HyprViz requires root privileges.\nPlease enter your root password:")
    if [[ -z "$ROOT_PASSWORD" ]]; then
        echo "Root password not provided. Skipping HyprViz installation."
        popd >/dev/null
        return 1
    fi
    
    # Create temporary askpass for root
    ROOT_ASKPASS=$(mktemp /tmp/root_askpass.XXXXXX.sh)
    echo '#!/bin/bash' > "$ROOT_ASKPASS"
    echo "echo '$ROOT_PASSWORD'" >> "$ROOT_ASKPASS"
    chmod +x "$ROOT_ASKPASS"
    
    export SUDO_ASKPASS="$ROOT_ASKPASS"
    sudo -A pacman -U --noconfirm "$PKG_FILE"
    
    # Cleanup
    rm -f "$ROOT_ASKPASS"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"  # Restore original
    
    popd >/dev/null
    rm -rf /tmp/hyprviz-bin
    
    echo "HyprViz installed successfully."
}

install_matuwall() {
    echo "Installing Matuwall wallpaper picker..."
    # Check if directory exists and delete it for fresh install
    if [[ -d ~/.local/share/Matuwall ]]; then
        echo "Existing Matuwall installation found. Removing it for fresh install..."
        rm -rf ~/.local/share/Matuwall
    fi
    git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall
    pushd ~/.local/share/Matuwall >/dev/null
    python -m venv --system-site-packages .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install .
    mkdir -p ~/.local/bin
    ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
    popd >/dev/null
}

install_wallpapers() {
    echo "Installing wallpapers..."
    if [[ -d ~/Pictures/Wallpapers ]]; then
        echo "Wallpaper folder already exists."
    else
        git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers || {
            mkdir -p ~/Pictures/Wallpapers
            cp ~/hyprtk/Wallpapers/* ~/Pictures/Wallpapers/ 2>/dev/null || true
        }
    fi
}

install_fonts() {
    echo "Installing fonts..."
    if [[ -d ~/.local/share/fonts ]]; then
        echo "User fonts folder exists, cloning repo..."
    else
        git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts || {
            mkdir -p ~/.local/share/fonts
            cp -r ~/hyprtk/fonts/* /usr/share/fonts/ 2>/dev/null || true
        }
    fi
}

install_icons_root() {
    echo "Installing Papirus icons for root user..."
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh
}

install_icons_user() {
    echo "Installing Papirus icons for user..."
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="~/.local/share/icons" sh
}

install_pywal16() {
    echo "Installing pywal16..."
    if [[ ! -f /usr/bin/wal ]]; then
        run_yay -S python-pywal16-git
    fi
    echo "Initializing pywal16 with default wallpaper..."
    wal -i ~/hyprtk/Wallpapers/default.png
    cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
    sudo -A cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
}

install_sddm_grub() {
    echo "Configuring SDDM and GRUB themes..."
    sudo -A mkdir -p /etc/sddm.conf.d
    sudo -A cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
    sudo -A rm -rf /usr/share/grub/themes/* /boot/grub/themes/*
    sudo -A cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/ 2>/dev/null || true
    sudo -A cp ~/hyprtk/sddm/theme.conf /usr/share/sddm/themes/Sugar-Candy/ 2>/dev/null || true
    # GRUB
    sudo -A sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sudo -A sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sudo -A sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    sudo -A sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo -A tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo -A tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo -A tee -a /etc/default/grub
    sudo -A grub-mkconfig -o /boot/grub/grub.cfg
    sudo -A sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
}

install_dotfiles() {
    echo "Creating symbolic links for dotfiles (force mode)..."
    # Ensure .config exists
    mkdir -p ~/.config
    mkdir -p ~/.local/bin

    
    _forceSymLink "alacritty" ~/.config/alacritty ~/hyprtk/alacritty ~/.config/alacritty
    _forceSymLink "ranger" ~/.config/ranger ~/hyprtk/ranger ~/.config/ranger
    _forceSymLink "vim" ~/.config/vim ~/hyprtk/vim ~/.config/vim
    _forceSymLink "nvim" ~/.config/nvim ~/hyprtk/nvim ~/.config/nvim
    _forceSymLink "starship" ~/.config/starship.toml ~/hyprtk/starship/starship.toml ~/.config/starship.toml
    _forceSymLink "rofi" ~/.config/rofi ~/hyprtk/rofi ~/.config/rofi
    _forceSymLink "dunst" ~/.config/dunst ~/hyprtk/dunst ~/.config/dunst
    _forceSymLink "wal" ~/.config/wal ~/hyprtk/wal ~/.config/wal
    _forceSymLink "btop" ~/.config/btop ~/hyprtk/btop ~/.config/btop
    _forceSymLink "gtk-3.0" ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0 ~/.config/gtk-3.0
    _forceSymLink "gtk-4.0" ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0 ~/.config/gtk-4.0
    _forceSymLink "themes" ~/.local/share/themes ~/hyprtk/themes ~/.local/share/themes
    _forceSymLink "icons" ~/.local/share/icons ~/hyprtk/papirus-icons/icons ~/.local/share/icons
    _forceSymLink "xfce4" ~/.config/xfce4 ~/hyprtk/xfce4 ~/.config/xfce4
    _forceSymLink "Thunar" ~/.config/Thunar ~/hyprtk/Thunar ~/.config/Thunar
    _forceSymLink "Mousepad" ~/.config/Mousepad ~/hyprtk/Mousepad ~/.config/Mousepad  
    # Remove existing ~/.config/hypr before symlinking
    remove_hypr_config
    _forceSymLink "hypr" ~/.config/hypr ~/hyprtk/hypr ~/.config/hypr
    _forceSymLink "fastfetch" ~/.config/fastfetch ~/hyprtk/fastfetch ~/.config/fastfetch
    _forceSymLink "waybar" ~/.config/waybar ~/hyprtk/waybar ~/.config/waybar
    _forceSymLink "swaylock" ~/.config/swaylock ~/hyprtk/swaylock ~/.config/swaylock
    _forceSymLink "swappy" ~/.config/swappy ~/hyprtk/swappy ~/.config/swappy
    _forceSymLink "hyprlogout" ~/.config/hyprlogout ~/hyprtk/hyprlogout ~/.config/hyprlogout
    _forceSymLink "waypaper" ~/.config/waypaper ~/hyprtk/waypaper ~/.config/waypaper
    _forceSymLink "ohmyposh" ~/.config/ohmyposh ~/hyprtk/ohmyposh ~/.config/ohmyposh
    _forceSymLink "matuwall" ~/.config/matuwall ~/hyprtk/matuwall ~/.config/matuwall
    _forceSymLink "wob" ~/.config/wob ~/hyprtk/wob ~/.config/wob
    _forceSymLink "standalone" ~/.local/bin ~/hyprtk/standalone ~/.local/bin
    _forceSymLink "zshrc" ~/.config/zshrc ~/hyprtk/zshrc ~/.config/zshrc
}

install_zsh() {
    echo "Installing ZSH..."
    
    # ----- Install zsh using a dedicated root password popup -----
    ROOT_PASSWORD=$(ask_root_password "Installing ZSH requires root privileges.\nPlease enter your root password:")
    if [[ -z "$ROOT_PASSWORD" ]]; then
        echo "Root password not provided. Skipping ZSH installation."
        return 1
    fi
    
    # Create temporary askpass for root
    ROOT_ASKPASS=$(mktemp /tmp/root_askpass.XXXXXX.sh)
    echo '#!/bin/bash' > "$ROOT_ASKPASS"
    echo "echo '$ROOT_PASSWORD'" >> "$ROOT_ASKPASS"
    chmod +x "$ROOT_ASKPASS"
    
    export SUDO_ASKPASS="$ROOT_ASKPASS"
    sudo -A pacman -S --noconfirm zsh
    
    # Cleanup temporary askpass
    rm -f "$ROOT_ASKPASS"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"  # Restore original
    
    # ----- Install Oh-My-Zsh (no root needed) -----
    echo "Installing Oh-My-Zsh..."
    rm -rf ~/.oh-my-zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
    
    # ----- Link .zshrc from dotfiles -----
    _forceSymLink ".zshrc" ~/.zshrc ~/hyprtk/.zshrc ~/.zshrc

    # ----- Configure custom zcompdump location in .zshrc -----
    ZSHRC_FILE=~/.zshrc
    if ! grep -q "ZSH_COMPDUMP=\"\$HOME/.cache/zsh/.zcompdump" "$ZSHRC_FILE" 2>/dev/null; then
        echo "Adding custom zcompdump configuration to .zshrc..."
        cat >> "$ZSHRC_FILE" << 'EOF'

# Custom zcompdump location
ZSH_COMPDUMP="$HOME/.cache/zsh/.zcompdump-${ZSH_VERSION}"
mkdir -p "$HOME/.cache/zsh"
autoload -Uz compinit
compinit -d "$ZSH_COMPDUMP"
EOF
    fi

    # ----- Set default shell for user and root (using a fresh root password) -----
    ROOT_PASSWORD2=$(ask_root_password "To set ZSH as the default shell for your user and root,\nplease enter the root password:")
    if [[ -n "$ROOT_PASSWORD2" ]]; then
        ROOT_ASKPASS2=$(mktemp /tmp/root_askpass.XXXXXX.sh)
        echo '#!/bin/bash' > "$ROOT_ASKPASS2"
        echo "echo '$ROOT_PASSWORD2'" >> "$ROOT_ASKPASS2"
        chmod +x "$ROOT_ASKPASS2"
        
        export SUDO_ASKPASS="$ROOT_ASKPASS2"
        sudo -A chsh -s /bin/zsh "$USER"
        sudo -A chsh -s /bin/zsh root
        
        rm -f "$ROOT_ASKPASS2"
        export SUDO_ASKPASS="$ASKPASS_SCRIPT"
        
        echo "Default shell changed to zsh for user '$USER' and root."
    else
        echo "Root password not provided. Skipping shell change."
    fi
}

install_ohmyposh() {
    echo "Installing Oh-my-posh..."
    
    # Clone AUR package (oh-my-posh-bin – binary version, fast)
    rm -rf /tmp/oh-my-posh-bin
    git clone https://aur.archlinux.org/oh-my-posh-bin.git /tmp/oh-my-posh-bin
    pushd /tmp/oh-my-posh-bin >/dev/null
    
    # Build as normal user
    echo "Building Oh-my-posh as user..."
    makepkg -s --noconfirm
    
    # Find the generated package file
    PKG_FILE=$(ls *.pkg.tar.zst 2>/dev/null | head -n1)
    if [[ -z "$PKG_FILE" ]]; then
        echo "Error: Failed to build Oh-my-posh package."
        popd >/dev/null
        return 1
    fi
    
    # Ask for root password to install
    ROOT_PASSWORD=$(ask_root_password "Installing Oh-my-posh requires root privileges.\nPlease enter your root password:")
    if [[ -z "$ROOT_PASSWORD" ]]; then
        echo "Root password not provided. Skipping Oh-my-posh installation."
        popd >/dev/null
        return 1
    fi
    
    ROOT_ASKPASS=$(mktemp /tmp/root_askpass.XXXXXX.sh)
    echo '#!/bin/bash' > "$ROOT_ASKPASS"
    echo "echo '$ROOT_PASSWORD'" >> "$ROOT_ASKPASS"
    chmod +x "$ROOT_ASKPASS"
    
    export SUDO_ASKPASS="$ROOT_ASKPASS"
    sudo -A pacman -U --noconfirm "$PKG_FILE"
    
    rm -f "$ROOT_ASKPASS"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"
    
    popd >/dev/null
    rm -rf /tmp/oh-my-posh-bin
    
    echo "Oh-my-posh installed successfully."
}

install_3dprinting() {
    echo "Installing 3D printing software..."
    run_yay -S orca-slicer-bin bambustudio-bin
}

# -----------------------------------------------------------------------------
# 5. Pre‑installation cleanup (runs before component selection)
# -----------------------------------------------------------------------------
echo "Performing pre‑installation cleanup..."
remove_kde_gnome
disable_other_dms_and_enable_sddm

# -----------------------------------------------------------------------------
# 6. Main menu – component selection
# -----------------------------------------------------------------------------
COMPONENTS=$(zenity --list --checklist \
    --title="Arch Linux Setup – Hyprland & XFCE" \
    --text="Select the components you wish to install.\nPassword will be cached – you won't be prompted again." \
    --column="Pick" --column="Component" --column="Description" \
    TRUE "yay" "Install yay AUR helper" \
    FALSE "chaotic_aur" "Enable Chaotic AUR (optional)" \
    TRUE "graphics_card" "Graphics card drivers (Intel/AMD/Nvidia/Virtualization)" \
    TRUE "hyprland" "Hyprland WM and core packages" \
    TRUE "xfce4" "XFCE4 desktop environment" \
    TRUE "system" "Base system packages (SDDM, bluetooth, etc.)" \
    TRUE "systemtools" "Timeshift, GParted, Cockpit, etc." \
    TRUE "filetools" "Thunar, Mousepad, shares plugin" \
    TRUE "terminaltools" "Alacritty, Kitty, Starship, Neovim, etc." \
    TRUE "webtools" "Chromium, Brave, GitHub Desktop" \
    TRUE "printers" "CUPS printing support" \
    TRUE "network" "NetworkManager, Samba, GVFS" \
    TRUE "media" "Audio/video tools (Pavucontrol, VLC, etc.)" \
    TRUE "pywal16" "Install and initialize pywal16" \
    TRUE "hyprviz" "HyprViz – Hyprland config tool" \
    TRUE "matuwall" "Matuwall wallpaper picker" \
    TRUE "wallpapers" "Download wallpapers collection" \
    TRUE "fonts" "Install fonts" \
    TRUE "icons_user" "Papirus icons for user" \
    TRUE "icons_root" "Papirus icons for root user" \
    TRUE "sddm_grub" "Theme SDDM and GRUB with wallpaper" \
    TRUE "zsh" "Install ZSH and Oh-My-Zsh" \
    TRUE "ohmyposh" "Install Oh-my-posh (prompt engine)" \
    FALSE "3dprinting" "OrcaSlicer and BambuStudio" \
    TRUE "dotfiles" "Symlink dotfiles (force overwrite)" \
    --width=900 --height=700 --separator="|")

if [ -z "$COMPONENTS" ]; then
    zenity --info --text="No components selected. Exiting."
    exit 0
fi

# -----------------------------------------------------------------------------
# 7. Run selected components with live output display
# -----------------------------------------------------------------------------
LOG_FILE="$HOME/hyprtk-install-$(date +%Y%m%d-%H%M%S).log"

{
    echo "============================================================"
    echo " Hyprtk Installation started at $(date)"
    echo " Selected components: ${COMPONENTS//|/, }"
    echo "============================================================"
    echo ""
    
    # Detect and display initramfs builder
    INITRAMFS_BUILDER=$(detect_initramfs_builder)
    echo "Detected initramfs builder: $INITRAMFS_BUILDER"
    echo ""

    IFS='|' read -ra SELECTED <<< "$COMPONENTS"
    for comp in "${SELECTED[@]}"; do
        echo "========== Starting: $comp =========="
        case "$comp" in
            yay)           install_yay ;;
            chaotic_aur)   install_chaotic_aur ;;
            graphics_card) install_graphics_card ;;
            hyprland)      install_hyprland ;;
            xfce4)         install_xfce4 ;;
            system)        install_system ;;
            systemtools)   install_systemtools ;;
            filetools)     install_filetools ;;
            terminaltools) install_terminaltools ;;
            webtools)      install_webtools ;;
            printers)      install_printers ;;
            network)       install_network ;;
            media)         install_media ;;
            pywal16)       install_pywal16 ;;
            hyprviz)       install_hyprviz ;;
            matuwall)      install_matuwall ;;
            wallpapers)    install_wallpapers ;;
            fonts)         install_fonts ;;
            icons_user)    install_icons_user ;;
            icons_root)    install_icons_root ;;
            sddm_grub)     install_sddm_grub ;;
            zsh)           install_zsh ;;
            ohmyposh)      install_ohmyposh ;;
            3dprinting)    install_3dprinting ;;
            dotfiles)      install_dotfiles ;;
            *) echo "Unknown component: $comp" ;;
        esac
        echo "========== Finished: $comp =========="
        echo ""
    done

    echo "============================================================"
    echo " Hyprtk Installation completed at $(date)"
    echo " Log saved to: $LOG_FILE"
    echo "============================================================"
} 2>&1 | tee "$LOG_FILE" | zenity --text-info \
    --title="Hyprtk Installation Progress" \
    --width=900 --height=600 \
    --auto-scroll \
    --font="Monospace 10" \
    --ok-label="Close"

# Final message
zenity --info --title="Done" \
    --text="Installation process finished.\n\nDetails have been logged to:\n$LOG_FILE\n\nYou may need to reboot for all changes to take effect." \
    --width=500

exit 0