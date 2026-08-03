#!/usr/bin/env bash
# Unified Hyprland & XFCE Installer
# Merges all 11 distro-specific installers into one
# by hyprtk (Kori Tk) (2026)

set -e

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================
MAGENTA='\033[35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD_MAGENTA='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'
BOLD_GREEN='\033[1;32m'
BOLD_RED='\033[1;31m'
BOLD_YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# SCRIPT DIRECTORY & GUM SETUP
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Gum paths - standalone first, then system
GUM="$SCRIPT_DIR/installer/standalone/gum"

gum() {
    "$GUM" "$@"
}

check_gum() {
    if [ -x "$GUM" ]; then
        return
    fi
    if command -v gum &>/dev/null; then
        GUM="$(command -v gum)"
        return
    fi
    gum_log "gum not found. Installing..." warning
    sudo pacman -S --noconfirm gum || true
    GUM="$(command -v gum)"
}

check_gum

# ============================================================================
# GUM STYLED FUNCTIONS
# ============================================================================
gum_style_header() {
    local title="$1"
    gum style \
        --border-foreground 5 \
        --border double \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$(printf "${BOLD_MAGENTA}${title}${NC}")"
}

gum_style_subheader() {
    local title="$1"
    gum style \
        --border-foreground 6 \
        --border double \
        --align center \
        --padding "0 3" \
        --margin "0 0" \
        "$(printf "${BOLD_CYAN}-> ${title}${NC}")"
}

gum_confirm() {
    local message="$1"
    if $GUM confirm --affirmative "Yes" --negative "No" "$message"; then
        return 0
    else
        return 1
    fi
}

gum_choose() {
    local prompt="$1"
    shift
    local options=("$@")
    $GUM choose "$prompt" "${options[@]}"
}

gum_spin() {
    local title="$1"
    shift
    local cmd="$*"
    $GUM spin --spinner dot --title "$title" -- bash -c "$cmd" || true
}

gum_log() {
    local message="$1"
    local style="${2:-info}"
    case $style in
        success)
            echo -e "${BOLD_GREEN}✓${NC} $message"
            ;;
        warning)
            echo -e "${BOLD_YELLOW}⚠${NC} $message"
            ;;
        error)
            echo -e "${BOLD_RED}✗${NC} $message"
            ;;
        *)
            echo -e "${BOLD_CYAN}→${NC} $message"
            ;;
    esac
}

# ============================================================================
# SOURCE LIBRARY SCRIPTS
# ============================================================================
source "$SCRIPT_DIR/installer/scripts/library.sh"

# ============================================================================
# DISTRO SELECTION TUI
# ============================================================================
gum style \
    --border-foreground 5 \
    --border double \
    --align center \
    --padding "1 3" \
    --margin "1 0" \
    "$(printf "${CYAN}HYPRTK DOTFILES${NC}")" \
    "$(printf "${CYAN}Hyprland Desktop Environment Installer${NC}")" \
    "" \
    "$(printf "${RED}DISCLAIMER${NC}")" \
    "$(printf "${WHITE}Installing these dotfiles may alter your system${NC}")" \
    "$(printf "${WHITE}configuration. A clean install is recommended for${NC}")" \
    "$(printf "${WHITE}best results.${NC}")"

gum style --foreground 5 --bold --padding "1 0" "Select your distribution:"

DISTROS=(
    "1) Arch Linux"
    "2) ArchBANG Linux"
    "3) Archcraft Linux"
    "4) Archman Linux"
    "5) BlueStar Linux"
    "6) CachyOS"
    "7) EndeavourOS"
    "8) Garuda Linux"
    "9) Kiro Linux (ArcoLinux Rebrand)"
    "10) Manjaro Linux"
    "11) My Personal Dotfiles"
    "12) RebornOS"
    "13) Exit"
)

SELECTED=$(gum choose \
    --height=13 \
    --cursor.foreground=5 \
    --selected.foreground=0 \
    --selected.background=5 \
    --item.foreground=6 \
    "${DISTROS[@]}")

if [[ -z "$SELECTED" || "$SELECTED" == "13) Exit" ]]; then
    printf '\033[1A\033[K'
    gum_log "Installation cancelled." warning
    exit 0
fi

DOTS="${SELECTED%%)*}"

if ! gum confirm --prompt.foreground=5 "Proceed with installation?"; then
    gum_log "Installation cancelled." warning
    exit 0
fi

# Map selection to distro ID
case $DOTS in
    1)  DISTRO_ID="arch" ;;
    2)  DISTRO_ID="archbang" ;;
    3)  DISTRO_ID="archcraft" ;;
    4)  DISTRO_ID="archman" ;;
    5)  DISTRO_ID="bslx" ;;
    6)  DISTRO_ID="cachy" ;;
    7)  DISTRO_ID="endeavour" ;;
    8)  DISTRO_ID="garuda" ;;
    9)  DISTRO_ID="kiro" ;;
    10) DISTRO_ID="manjaro" ;;
    11) DISTRO_ID="my" ;;
    12) DISTRO_ID="reborn" ;;
    *)  DISTRO_ID="arch" ;;
esac

# ============================================================================
# COPY DISTRO-SPECIFIC OS-RELEASE
# ============================================================================
gum_log "Setting up distro: $DISTRO_ID" info

if [ -f "$SCRIPT_DIR/installer/os-release/os-release-$DISTRO_ID" ]; then
    cp "$SCRIPT_DIR/installer/os-release/os-release-$DISTRO_ID" "$SCRIPT_DIR/installer/os-release/os-release"
    gum_log "os-release configured for $DISTRO_ID" success
else
    gum_log "os-release file not found for $DISTRO_ID, using default" warning
fi

# ============================================================================
# MAIN INSTALLATION FUNCTION
# ============================================================================
main() {
    gum_style_header "HYPRTK INSTALLER"
    
    DISTRO_NAME=$(get_distro_name "$DISTRO_ID")
    gum_log "Distribution: $DISTRO_NAME" success
    
    if ! is_supported_distro "$DISTRO_ID"; then
        gum_log "Unsupported distribution: $DISTRO_NAME" error
        gum_log "Supported: Arch, Garuda, CachyOS, Manjaro, EndeavourOS, Archcraft, Archman, ArchBang, BSLX, Kiro, RebornOS" info
        exit 1
    fi
    
    gum_style_header "WELCOME"
    gum_log "Installing both Hyprland and XFCE environments" info
    gum_log "If you choose No on either, the installer will fail" info
    gum_log "You will be asked for Root password to proceed" info
    
    gum_style_subheader "Removing leftover Packages"
    get_distro_removal_command "$DISTRO_ID"
    
    gum_style_subheader "Starting Installation Process"
    
    gum_style_subheader "Load Installation Libraries"
    sh ~/hyprtk/installer/scripts/set-timezone.sh
    
    gum_style_subheader "Install Yay"
    if sudo pacman -Qs yay > /dev/null ; then
        gum_log "yay is installed" success
    else
        gum_log "yay is not installed, installing now!" warning
        _installPackagesPacman "base-devel"
        git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git || true
        cd ~/Downloads/yay-git || true
        makepkg -si || true
        cd ~/hyprtk/ || true
    fi
    
    gum_confirm "DO YOU WANT TO START THE INSTALLATION NOW?" || exit 1
    
    # ============================================================================
    # GRAPHICS CARD DETECTION
    # ============================================================================
    gum_style_subheader "Graphics Card Detection"
    
    GRAPHICSCARD=$(gum choose \
        --header "Which Graphics Card do you have?" \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "1) Intel" \
        "2) AMD" \
        "3) Nvidia" \
        "4) Virtualization (QEMU/virt & VMware)")
    
    case "$GRAPHICSCARD" in
        *"Intel"*)
            gum_style_subheader "Installing Intel Graphics Drivers"
            _installOrUpdatePacman xf86-video-intel
            _installOrUpdatePacman mesa
            _installOrUpdatePacman vulkan-intel
            ;;
        *"AMD"*)
            gum_style_subheader "Installing AMD Graphics Drivers"
            _installOrUpdatePacman xf86-video-amdgpu
            _installOrUpdatePacman mesa
            _installOrUpdatePacman vulkan-radeon
            _installOrUpdatePacman vdpauinfo
            _installOrUpdatePacman corectrl
            _installOrUpdatePacman libvdpau
            sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf || true
            update_initramfs_config "" "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
            ;;
        *"Nvidia"*)
            gum_style_subheader "Installing Nvidia Graphics Drivers"
            sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub || true
            sudo grub-mkconfig -o /boot/grub/grub.cfg || true
            sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf || true
            echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf || true
            _installOrUpdatePacman nvidia-open-dkms
            _installOrUpdatePacman nvidia-utils
            _installOrUpdatePacman nvidia-settings
            _installOrUpdatePacman qt5-wayland
            _installOrUpdatePacman qt5ct
            _installOrUpdatePacman qt6-wayland
            _installOrUpdatePacman qt6ct
            _installOrUpdatePacman libva
            _installOrUpdateYay libva-nvidia-driver-git
            update_initramfs_config "" "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
            ;;
        *"Virtualization"*)
            gum_style_subheader "Installing Virtualization Guest Drivers"
            _installOrUpdatePacman qemu-guest-agent
            _installOrUpdatePacman spice-vdagent
            _installOrUpdatePacman xf86-video-qxl
            _installOrUpdatePacman mesa
            _installOrUpdateYay xf86-video-vmware
            _installOrUpdateYay open-vm-tools
            sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
            sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
            sudo systemctl enable --now vmtoolsd 2>/dev/null || true
            ;;
        *)
            gum_style_subheader "Installing AMD Graphics Drivers (Default)"
            _installOrUpdatePacman xf86-video-amdgpu
            _installOrUpdatePacman mesa
            _installOrUpdatePacman vulkan-radeon
            _installOrUpdatePacman vdpauinfo
            _installOrUpdatePacman corectrl
            _installOrUpdatePacman libvdpau
            sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf || true
            update_initramfs_config "" "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
            ;;
    esac
    
    gum_confirm "DO YOU WANT TO INSTALL THE CORE APPS NOW?" || exit 1
    
    # ============================================================================
    # HYPRLAND PACKAGES
    # ============================================================================
    gum_style_subheader "Installing Hyprland"
    
    _installOrUpdatePacman hyprland
    _installOrUpdatePacman xdg-desktop-portal-wlr
    _installOrUpdatePacman swayidle
    _installOrUpdatePacman swappy
    _installOrUpdatePacman cliphist
    _installOrUpdatePacman xorg-xhost
    _installOrUpdatePacman nwg-look
    _installOrUpdatePacman mission-center
    _installOrUpdatePacman curl
    _installOrUpdatePacman imagemagick
    _installOrUpdatePacman jq
    _installOrUpdatePacman bc
    _installOrUpdatePacman brightnessctl
    _installOrUpdatePacman playerctl
    _installOrUpdatePacman libadwaita
    _installOrUpdatePacman gtk-layer-shell
    _installOrUpdatePacman python
    _installOrUpdatePacman python-pip
    _installOrUpdatePacman python-virtualenv
    _installOrUpdatePacman python-gobject
    _installOrUpdatePacman gtk4
    _installOrUpdatePacman wob
    
    _installOrUpdateYay awww
    _installOrUpdateYay swaylock-effects
    _installOrUpdateYay gvfs-afc
    _installOrUpdateYay gvfs-goa
    _installOrUpdateYay gvfs-gphoto2
    _installOrUpdateYay gvfs-mtp
    _installOrUpdateYay gvfs-nfs
    _installOrUpdateYay gvfs-smb
    _installOrUpdateYay 7zip
    _installOrUpdateYay unzip
    _installOrUpdateYay unrar
    _installOrUpdateYay waybar-git
    
    gum_log "Hyprland packages installed" success
    
    # ============================================================================
    # XFCE4 PACKAGES
    # ============================================================================
    gum_style_subheader "Installing XFCE4"
    
    _installOrUpdatePacman xfce4
    _installOrUpdatePacman xfce4-goodies
    _installOrUpdatePacman parole
    
    _installOrUpdateYay tumbler-extra-thumbnailers
    
    gum_log "XFCE4 packages installed" success
    
    # ============================================================================
    # FILE TOOLS
    # ============================================================================
    gum_style_subheader "Installing File Tools"
    
    _installOrUpdatePacman thunar
    _installOrUpdatePacman mousepad
    
    _installOrUpdateYay thunar-shares-plugin
    
    gum_log "File tools installed" success
    
    # ============================================================================
    # WEB TOOLS
    # ============================================================================
    gum_style_subheader "Installing Web Tools"
    
    _installOrUpdatePacman chromium
    
    _installOrUpdateYay brave-bin
    _installOrUpdateYay github-desktop-bin
    
    gum_log "Web tools installed" success
    
    # ============================================================================
    # PRINTERS
    # ============================================================================
    gum_style_subheader "Installing Printer Support"
    
    _installOrUpdateYay cups
    _installOrUpdateYay cups-pdf
    _installOrUpdateYay cups-filters
    _installOrUpdateYay nss-mdns
    _installOrUpdateYay system-config-printer
    _installOrUpdateYay cups-browsed
    _installOrUpdateYay libusb
    _installOrUpdateYay ipp-usb
    _installOrUpdateYay xdg-utils
    _installOrUpdateYay colord
    _installOrUpdateYay logrotate
    
    gum_log "Printer support installed" success
    
    # ============================================================================
    # NETWORK
    # ============================================================================
    gum_style_subheader "Installing Network Packages"
    
    _installOrUpdatePacman networkmanager
    _installOrUpdatePacman network-manager-applet
    _installOrUpdatePacman git
    _installOrUpdatePacman freerdp
    _installOrUpdatePacman curl
    _installOrUpdatePacman gvfs
    _installOrUpdatePacman gvfs-afc
    _installOrUpdatePacman gvfs-dnssd
    _installOrUpdatePacman gvfs-goa
    _installOrUpdatePacman gvfs-gphoto2
    _installOrUpdatePacman gvfs-mtp
    _installOrUpdatePacman gvfs-nfs
    _installOrUpdatePacman gvfs-onedrive
    _installOrUpdatePacman gvfs-smb
    _installOrUpdatePacman gvfs-wsdd
    _installOrUpdatePacman ntfs-3g
    _installOrUpdatePacman samba
    
    gum_log "Network packages installed" success
    
    # ============================================================================
    # MEDIA
    # ============================================================================
    gum_style_subheader "Installing Media Packages"
    
    _installOrUpdatePacman xclip
    _installOrUpdatePacman pamixer
    _installOrUpdatePacman wf-recorder
    _installOrUpdatePacman pavucontrol
    _installOrUpdatePacman tumbler
    _installOrUpdatePacman vlc
    _installOrUpdatePacman mpv
    _installOrUpdatePacman ffmpeg
    
    _installOrUpdateYay hyprquickframe-git
    
    gum_log "Media packages installed" success
    
    # ============================================================================
    # TERMINAL TOOLS
    # ============================================================================
    gum_style_subheader "Installing Terminal Tools"
    
    _installOrUpdatePacman eza
    _installOrUpdatePacman micro
    _installOrUpdatePacman xfce4-terminal
    _installOrUpdatePacman btop
    _installOrUpdatePacman alacritty
    _installOrUpdatePacman kitty
    _installOrUpdatePacman starship
    _installOrUpdatePacman ranger
    _installOrUpdatePacman nano
    _installOrUpdatePacman figlet
    _installOrUpdatePacman neovim
    
    _installOrUpdateYay fastfetch
    
    gum_log "Terminal tools installed" success
    
    # ============================================================================
    # SYSTEM TOOLS
    # ============================================================================
    gum_style_subheader "Installing System Tools"
    
    _installOrUpdatePacman timeshift
    _installOrUpdatePacman file-roller
    _installOrUpdatePacman gparted
    _installOrUpdatePacman xfce4-power-manager
    _installOrUpdatePacman rofi
    _installOrUpdatePacman dunst
    _installOrUpdatePacman cockpit
    
    _installOrUpdateYay gnome-disk-utility
    
    gum_log "System tools installed" success
    
    # ============================================================================
    # SYSTEM PACKAGES
    # ============================================================================
    gum_style_subheader "Installing System Packages"
    
    _installOrUpdatePacman sddm
    _installOrUpdatePacman blueman
    _installOrUpdatePacman pacman-contrib
    _installOrUpdatePacman fzf
    _installOrUpdatePacman font-manager
    _installOrUpdatePacman awesome-terminal-fonts
    _installOrUpdatePacman ttf-font-awesome
    _installOrUpdatePacman ttf-fira-sans
    _installOrUpdatePacman ttf-fira-code
    _installOrUpdatePacman ttf-firacode-nerd
    _installOrUpdatePacman exa
    _installOrUpdatePacman python-pip
    _installOrUpdatePacman python-psutil
    _installOrUpdatePacman python-rich
    _installOrUpdatePacman python-click
    _installOrUpdatePacman xdg-desktop-portal-gtk
    _installOrUpdatePacman xdg-user-dirs
    _installOrUpdatePacman xdg-user-dirs-gtk
    _installOrUpdatePacman os-prober
    _installOrUpdatePacman polkit-gnome
    _installOrUpdatePacman gnome-keyring
    _installOrUpdatePacman pcp
    _installOrUpdatePacman pcp-gui
    _installOrUpdatePacman gtk4-layer-shell
    _installOrUpdatePacman hyprpicker
    
    sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm || true
    
    _installOrUpdateYay bibata-cursor-theme
    _installOrUpdateYay trizen
    _installOrUpdateYay sublime-text-4
    _installOrUpdateYay sddm-theme-sugar-candy-git
    _installOrUpdateYay pacseek
    
    gum_log "System packages installed" success
    
    # ============================================================================
    # 3D PRINTING
    # ============================================================================
    gum_style_subheader "Installing 3D Printing"
    
    _installOrUpdateYay orca-slicer-bin
    _installOrUpdateYay bambustudio-bin
    
    gum_log "3D printing packages installed" success
    
    # ============================================================================
    # HYPRTK CONFIGURATION
    # ============================================================================
    gum_log "Installed required Packages" success
    
    gum_style_subheader "Install Pywal16"
    if [ -f /usr/bin/wal ]; then
        gum_log "pywal16 already installed" success
    else
        gum_spin "Installing Pywal16..." yay --noconfirm -S python-pywal16-git
    fi
    gum_log "Pywal16 Installed" success
    
    gum_style_subheader "Install Wallpapers"
    sh ~/hyprtk/hypr/packages/wallpapers.sh
    gum_log "Wallpapers Installed" success
    
    gum_style_subheader "Install Fonts"
    sh ~/hyprtk/hypr/packages/fonts.sh
    gum_log "Fonts Installed" success
    
    gum_style_subheader "Install Icons Root"
    gum_spin "Installing Icons..." 'wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh'
    gum_log "Icons Installed" success
    
    gum_style_subheader "Initiating Pywal16"
    
    if uses_cache_wallpaper "$DISTRO_ID"; then
        wal -i ~/.cache/current-wallpaper.png || true
    else
        wal -i ~/hyprtk/assets/Wallpapers/default.png || true
    fi
    
    gum_log "pywal16 initiated" success
    cp ~/hyprtk/assets/Wallpapers/default.png ~/.cache/current-wallpaper.png || true
    sudo mkdir -p /root/.cache && sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png || true
    
    if needs_grub_wallpaper "$DISTRO_ID"; then
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png || true
    fi
    
    xdg-user-dirs-update --force || true
    xdg-user-dirs-gtk-update --force || true
    gum_log "Pywal16 Initiated" success
    
    gum_style_subheader "Hyprland Configuration"
    gum_log "by Kori Tk (2026)" info
    
    gum_confirm "DO YOU WANT TO START THE INSTALLATION NOW?" || exit 1
    
    gum_style_subheader "Launch Thunar to generate xfconf"
    thunar &
    gum_spin "Waiting for Thunar..." sleep 3
    killall thunar || true
    
    gum_style_subheader "Enabling Bluetooth"
    gum_spin "Enabling Bluetooth..." bash -c "sudo systemctl start bluetooth && sudo systemctl enable bluetooth"
    
    gum_style_subheader "Enabling Cockpit"
    sudo cp ~/hyprtk/installer/os-release/os-release /usr/lib/ || true
    
    if has_cachyos_branding "$DISTRO_ID"; then
        sudo cp ~/hyprtk/installer/os-release/os-release /run/systemd/propagate/.os-release-stage/ || true
        sudo cp ~/hyprtk/installer/os-release/os-release /run/user/$UID/systemd/propagate/.os-release-stage/ || true
        sudo cp ~/hyprtk/installer/os-release/cachyos-branding /usr/share/libalpm/scripts/ || true
        sudo bash /usr/share/libalpm/scripts/cachyos-branding || true
    fi
    
    sudo cp ~/hyprtk/configs/User-Management/manage-users.desktop /usr/share/applications/ || true
    gum_spin "Enabling Cockpit..." bash -c "sudo systemctl enable --now cockpit.socket && sudo systemctl start cockpit.socket"
    
    gum_style_subheader "Enabling Samba"
    sudo cp ~/hyprtk/configs/smb/smb.conf /etc/samba/ || true
    gum_spin "Enabling Samba..." bash -c "sudo systemctl enable smb nmb && sudo systemctl start smb nmb && sudo systemctl restart smb nmb"
    gum_log "Please update interfaces in /etc/samba/smb.conf with your IP address" warning
    
    gum_style_header "IMPORTANT - NVIDIA Graphics Card"
    gum_log "If you have NVIDIA, follow instructions in ~/hyprtk/hypr/nvidia.lua" info
    
    gum_style_subheader "SDDM & GRUB Configuration"
    sh ~/hyprtk/hypr/packages/sddm-check.sh
    sh ~/hyprtk/hypr/packages/sddmgrub.sh
    
    gum_style_subheader "hyprtk Dotfiles Installation"
    gum_log "by Kori Tk (2026)" info
    gum_log "Symbolic links will be created from ~/hyprtk to ~/.config/" info
    gum_log "Answer No to keep your personal versions" info
    
    gum_confirm "DO YOU WANT TO START THE INSTALLATION NOW?" || exit 1
    
    gum_style_subheader "Check .config directory"
    if [ -d ~/.config ]; then
        gum_log ".config folder already exists" success
    else
        mkdir ~/.config
        gum_log ".config folder created" info
    fi
    
    gum_style_subheader "Create Symbolic Links"
    
    _installSymLink alacritty ~/.config/alacritty ~/hyprtk/configs/alacritty/ ~/.config
    _installSymLink ranger ~/.config/ranger ~/hyprtk/configs/ranger/ ~/.config
    _installSymLink vim ~/.config/vim ~/hyprtk/configs/vim/ ~/.config
    _installSymLink nvim ~/.config/nvim ~/hyprtk/configs/nvim/ ~/.config
    _installSymLink starship ~/.config/starship.toml ~/hyprtk/configs/starship/starship.toml ~/.config/starship.toml
    _installSymLink rofi ~/.config/rofi ~/hyprtk/configs/rofi/ ~/.config
    _installSymLink dunst ~/.config/dunst ~/hyprtk/configs/dunst/ ~/.config
    _installSymLink wal ~/.config/wal ~/hyprtk/configs/wal/ ~/.config
    _installSymLink btop ~/.config/btop ~/hyprtk/configs/btop/ ~/.config
    
    gum_style_subheader "Re-Initiating Pywal16"
    
    if uses_cache_wallpaper "$DISTRO_ID"; then
        wal -i ~/.cache/current-wallpaper.png || true
    else
        wal -i ~/hyprtk/assets/Wallpapers/default.png || true
    fi
    
    gum_log "Pywal16 templates initiated" success
    
    gum_style_subheader "Install GTK hyprtk"
    _installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/configs/gtk/gtk-3.0/ ~/.config/
    _installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/configs/gtk/gtk-4.0/ ~/.config/
    _installSymLink themes ~/.local/share/themes ~/hyprtk/assets/themes ~/.local/share/
    _installSymLink icons ~/.local/share/icons ~/hyprtk/configs/papirus-icons/icons ~/.local/share/
    
    gum_style_subheader "Install Xfce hyprtk"
    _installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/configs/xfce4 ~/.config/
    _installSymLink Thunar ~/.config/Thunar ~/hyprtk/configs/Thunar ~/.config/
    _installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/configs/Mousepad ~/.config/
    
    gum_style_subheader "Install Hyprland hyprtk"
    
    if needs_hypr_backup "$DISTRO_ID"; then
        mv ~/.config/hypr ~/.config/hypr-old
    fi
    
    _installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/ ~/.config
    _installSymLink fastfetch ~/.config/fastfetch ~/hyprtk/configs/fastfetch/ ~/.config
    _installSymLink waybar ~/.config/waybar ~/hyprtk/configs/waybar/ ~/.config
    _installSymLink swaylock ~/.config/swaylock ~/hyprtk/configs/swaylock/ ~/.config
    _installSymLink swappy ~/.config/swappy ~/hyprtk/configs/swappy/ ~/.config
    _installSymLink hyprlogout ~/.config/hyprlogout ~/hyprtk/configs/hyprlogout/ ~/.config
    _installSymLink waypaper ~/.config/waypaper ~/hyprtk/configs/waypaper/ ~/.config
    _installSymLink zshrc ~/.config/zshrc ~/hyprtk/configs/zshrc/ ~/.config
    _installSymLink ohmyposh ~/.config/ohmyposh ~/hyprtk/configs/ohmyposh/ ~/.config
    _installSymLink matuwall ~/.config/matuwall ~/hyprtk/configs/matuwall/ ~/.config
    _installSymLink wob ~/.config/wob ~/hyprtk/configs/wob/ ~/.config
    [ -L ~/.local/bin ] && rm -f ~/.local/bin
    mkdir -p ~/.local/bin || true
    
    gum_style_subheader "Install ZSH"
    sudo pacman -S zsh --noconfirm || true
    _checkAndInstallOhMyZsh
    
    gum_style_subheader "Install ZSH Plugins"
    _installZshPlugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
    _installZshPlugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    _installZshPlugin "fast-syntax-highlighting" "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
    
    gum_style_subheader "Update .zshrc"
    _installSymLink .zshrc ~/.zshrc ~/hyprtk/.zshrc ~/.zshrc
    sudo chsh -s /bin/zsh || true
    chsh -s /bin/zsh || true
    gum_log ".zshrc Updated" success
    _installSymLink standalone ~/.local/bin ~/hyprtk/installer/standalone/ ~/.local/bin
    _installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/hyprtk/configs/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh
    [ -d "$HOME/dotfiles" ] && rm -R $HOME/dotfiles || true
    
    gum_style_subheader "Setup Root User Config"
    sudo cp -r ~/hyprtk/configs/root / || true
    gum_log "Copying Config and Themes to ROOT User" info
    echo -e 'Defaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers || true
    gum_log "Setup Password Feedback when entering SUDO password" info
    
    gum_style_header "Setup Complete"
    gum_log "Update keyboard layout in ~/hyprtk/hypr/input.lua" warning
    gum_log "Update screen resolution in ~/hyprtk/hypr/monitors.lua" warning
    gum_log "Reboot your system and Enjoy!" success
    
    gum style \
        --foreground 6 \
        --border-foreground 5 \
        --border double \
        --padding "1 3" \
        --margin "1 0" \
        "Installation complete" \
        "github.com/hyprtk/dotfiles"
}

# Run the main function
main "$@"
