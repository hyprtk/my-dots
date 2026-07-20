#!/usr/bin/env bash

# Hyprtk-On-Arch - Unified Desktop Environment Installer
# Supports: Arch, ArchBang, ArchCraft, ArchMan, BSLx, CachyOS,
#           EndeavourOS, Garuda, Kiro, Manjaro, RebornOS
# by hyprtk (Kori Tk) (2026)

MAGENTA=$'\033[35m'
CYAN=$'\033[0;36m'
WHITE=$'\033[0;37m'
RED=$'\033[1;31m'
NC=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install.log"
DISTRO=""

GUM="$SCRIPT_DIR/common/standalone/gum"

gum() {
    "$GUM" "$@"
}

# ---- Logging ----
LOG_FILE="${SCRIPT_DIR}/install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# Run a command with stdout logged; gum is called directly (needs real terminal)
log_run() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RUN: $*" >> "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1
}

# ---- Error Handling ----
set -euo pipefail

handle_error() {
    local exit_code=$?
    local line_no=$1
    err "Installation failed at line $line_no (exit code: $exit_code)"
    err "Check $LOG_FILE for details"
    exit "$exit_code"
}

trap 'handle_error $LINENO' ERR

# ---- Utility: gum style header ----
header_step() {
    log "Step: $1"
    gum style --border double --align center --padding "1 3" --margin "1 0" --border-foreground 5 "$1"
}

# ---- Gum Check ----
check_gum() {
    if [ -x "$GUM" ]; then
        return
    fi
    if command -v gum &>/dev/null; then
        GUM="$(command -v gum)"
        return
    fi
    echo -e "${CYAN}gum not found. Installing...${NC}"
    sudo pacman -S --noconfirm gum
    GUM="$(command -v gum)"
}

# ---- Distro Detection ----
detect_distro() {
    local detected=""

    if [ -f /etc/os-release ]; then
        local id
        id=$(grep -oP '^ID=.*' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        case "$id" in
            arch) detected="arch" ;;
            archbang) detected="archbang" ;;
            archcraft) detected="archcraft" ;;
            archman) detected="archman" ;;
            bslx) detected="bslx" ;;
            cachyos) detected="cachy" ;;
            endeavouros) detected="endeavour" ;;
            garuda) detected="garuda" ;;
            kiro) detected="kiro" ;;
            manjaro) detected="manjaro" ;;
            rebornos) detected="reborn" ;;
        esac
    fi

    if [ -n "$detected" ]; then
        echo ""
        DISTRO="$detected"
        gum style --foreground 5 "Detected distribution: $(gum style --bold --foreground 6 "$detected")"
        echo ""
        if gum confirm --prompt.foreground=5 "Use detected distro?" --default=true; then
            log "Selected distro: $DISTRO"
            return
        fi
    fi

    local distros=("arch" "archbang" "archcraft" "archman" "bslx" "cachy" "endeavour" "garuda" "kiro" "manjaro" "reborn")
    echo ""
    DISTRO=$(gum filter --header "Select your distribution:" \
        --header.foreground=5 \
        --placeholder "Type to filter..." \
        --indicator.foreground=5 \
        --selected-indicator.foreground=5 \
        --match.foreground=6 \
        --prompt.foreground=5 \
        "${distros[@]}" || true)
    if [ -z "$DISTRO" ]; then
        printf '\033[1A\033[K'
        echo -e "${MAGENTA}Installation cancelled.${NC}"
        exit 0
    fi
    log "Selected distro: $DISTRO"
}

# ---- Pre-flight Checks ----
preflight() {
    clear

    gum style \
        --border-foreground 5 \
        --border double \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$(printf "${CYAN}Hyprtk-On-Arch Installer${NC}")" \
        "$(printf "${CYAN}Unified Desktop Environment for Arch Linux & derivatives${NC}")"

    if [ "$(id -u)" -eq 0 ]; then
        err "Do not run as root. Run as a regular user with sudo access."
        exit 1
    fi

    if ! command -v sudo &>/dev/null; then
        err "sudo is required but not installed."
        exit 1
    fi

    if ! sudo -v; then
        err "User does not have sudo access."
        exit 1
    fi

    check_gum
    detect_distro
}

# ---- Intro ----
show_intro() {
    gum style \
        --border-foreground 5 \
        --border double \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$(printf "${MAGENTA}Installation Overview${NC}")" \
        "" \
        "$(printf "${MAGENTA}Distribution:${NC}  ${CYAN}${DISTRO}${NC}")" \
        "" \
        "$(printf "${CYAN}You will now be guided through these steps:${NC}")" \
        "$(printf "${CYAN}  1. Graphics Card${NC}")" \
        "$(printf "${CYAN}  2. Package Groups${NC}")" \
        "$(printf "${CYAN}  3. Dotfiles${NC}")" \
        "$(printf "${CYAN}  4. Services${NC}")" \
        "" \
        "$(printf "${CYAN}All items are pre-selected. Just uncheck what you don't want.${NC}")"
    echo ""
}

# ---- Helper: install packages from file ----
install_from_list() {
    local pkg_file="$1"
    if [ ! -f "$pkg_file" ]; then
        warn "Package list not found: $pkg_file"
        return
    fi
    log "Installing packages from $(basename "$pkg_file")..."
    sudo pacman -S --noconfirm --needed - < "$pkg_file" || {
        warn "Some packages in $(basename "$pkg_file") failed. Continuing..."
    }
}

# ---- Graphics Card Selection ----
GRAPHICS="intel"

select_graphics() {
    header_step "Graphics Card"

    local choice
    choice=$(gum choose \
        --header "Select your graphics card:" \
        --header.foreground=5 \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "Intel (i915 driver)" \
        "AMD (amdgpu driver)" \
        "Nvidia (nvidia-open driver)" \
        "Virtual Machine (virtio/vmwgfx)" \
        || true)
    if [[ -z "$choice" ]]; then
        printf '\033[1A\033[K'
        echo -e "${MAGENTA}Installation cancelled.${NC}"
        exit 0
    fi

    case "$choice" in
        "Intel (i915 driver)") GRAPHICS="intel" ;;
        "AMD (amdgpu driver)") GRAPHICS="amd" ;;
        "Nvidia (nvidia-open driver)") GRAPHICS="nvidia" ;;
        "Virtual Machine (virtio/vmwgfx)") GRAPHICS="virt" ;;
    esac

    log "Selected graphics: $GRAPHICS"
    echo ""
}

# ---- Package Groups Selection ----
PACKAGE_GROUPS=()

select_package_groups() {
    header_step "Package Groups"

    local groups=(
        "Hyprland:Core Hyprland compositor + essential tools"
        "XFCE4:XFCE4 desktop environment"
        "File Tools:Thunar, ranger, gvfs, Archive Manager"
        "Web Tools:Firefox, Chromium, qutebrowser"
        "Printers:HP Printing + CUPS"
        "Network:NetworkManager, nm-applet, OpenVPN"
        "Media:mpv, vlc, audacity, obs-studio, spotify"
        "Terminal Tools:kitty, tmux, htop, btop, lazygit"
        "System Tools:pavucontrol, virt-manager, timeshift"
        "System:grub-customizer, gparted, gsmartcontrol"
        "HyprViz:Visual effects for Hyprland"
        "SDDM Check:Ensure SDDM is installed"
        "SDDM Grub:SDDM + GRUB theme configuration"
        "Matuwall:Auto wallpaper color scheme tool"
        "Fonts:Font packages (nerd-fonts, noto, etc.)"
        "Wallpapers:Wallpaper assets"
        "Bluetooth:bluez, bluez-utils, blueman"
        "Cockpit:Web-based system administration"
        "Samba:File sharing (SMB/CIFS)"
        "3D Printing:PrusaSlicer, cura, openscad"
        "AUR Helper:yay AUR helper"
        "Pywal16:python-pywal16-git for color generation"
    )

    local items=()
    local selected_flags=()
    for g in "${groups[@]}"; do
        case "$g" in
            "AUR Helper:"* | "3D Printing:"*)
                items+=("$g")
                ;;
            *)
                selected_flags+=("--selected" "$g")
                items+=("$g")
                ;;
        esac
    done

    local choices
    choices=$(gum choose --no-limit \
        --header "Package groups (SPACE to toggle, ENTER to confirm):" \
        --header.foreground=5 \
        --height=25 \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "${selected_flags[@]}" \
        "${items[@]}" || true)

    if [[ -z "$choices" ]]; then
        printf '\033[1A\033[K'
        echo -e "${MAGENTA}No package groups selected. Skipping.${NC}"
        echo ""
        return
    fi

    PACKAGE_GROUPS=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local group_name="${line%%:*}"
            PACKAGE_GROUPS+=("$group_name")
        fi
    done <<< "$choices"

    log "Selected package groups: ${PACKAGE_GROUPS[*]}"
    echo ""
}

# ---- Dotfiles Selection ----
DOTFILES=()

select_dotfiles() {
    header_step "Dotfiles"

    local items=(
        "General:alacritty"
        "General:btop"
        "General:dunst"
        "General:ranger"
        "General:rofi"
        "General:starship"
        "General:vim"
        "General:nvim"
        "General:wal"
        "GTK:gtk-3.0"
        "GTK:gtk-4.0"
        "GTK:themes"
        "GTK:icons"
        "Xfce:xfce4"
        "Xfce:Thunar"
        "Xfce:Mousepad"
        "Hyprland:hypr"
        "Hyprland:fastfetch"
        "Hyprland:waybar"
        "Hyprland:swaylock"
        "Hyprland:swappy"
        "Hyprland:hyprlogout"
        "Hyprland:waypaper"
        "Hyprland:zshrc"
        "Hyprland:ohmyposh"
        "Hyprland:matuwall"
        "Hyprland:wob"
    )

    local args=()
    for item in "${items[@]}"; do
        args+=("--selected" "$item")
    done

    local choices
    choices=$(gum choose --no-limit \
        --header "Dotfiles (SPACE to toggle, ENTER to confirm):" \
        --header.foreground=5 \
        --height=28 \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "${args[@]}" \
        -- "${items[@]}" || true)

    if [[ -z "$choices" ]]; then
        printf '\033[1A\033[K'
        echo -e "${MAGENTA}No dotfiles selected. Skipping.${NC}"
        echo ""
        return
    fi

    DOTFILES=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local item_name="${line#*:}"
            DOTFILES+=("$item_name")
        fi
    done <<< "$choices"

    log "Selected dotfiles: ${DOTFILES[*]}"
    echo ""
}

# ---- Services Selection ----
SERVICES=()

select_services() {
    header_step "Services"

    local items=(
        "Bluetooth:bluez, blueman - wireless audio/devices"
        "Cockpit:Web-based server management console"
        "Samba:File/print sharing (SMB/CIFS protocol)"
    )

    local args=()
    for item in "${items[@]}"; do
        args+=("--selected" "$item")
    done

    local choices
    choices=$(gum choose --no-limit \
        --header "Services (SPACE to toggle, ENTER to confirm):" \
        --header.foreground=5 \
        --height=3 \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "${args[@]}" \
        -- "${items[@]}" || true)

    if [[ -z "$choices" ]]; then
        printf '\033[1A\033[K'
        echo -e "${MAGENTA}No services selected. Skipping.${NC}"
        echo ""
        return
    fi

    SERVICES=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local svc="${line%%:*}"
            SERVICES+=("$svc")
        fi
    done <<< "$choices"

    log "Selected services: ${SERVICES[*]}"
    echo ""
}

# ---- Review & Install ----
review_install() {
    header_step "Review & Install"

    local rl=()
    rl+=("$(printf "${MAGENTA}Distribution:${NC}  ${CYAN}${DISTRO}${NC}")")
    rl+=("$(printf "${MAGENTA}Graphics:${NC}      ${CYAN}${GRAPHICS}${NC}")")

    if [[ ${#PACKAGE_GROUPS[@]} -gt 0 ]]; then
        rl+=("$(printf "${MAGENTA}Package Groups:${NC}")")
        for item in "${PACKAGE_GROUPS[@]}"; do
            rl+=("  ${CYAN}• ${item}${NC}")
        done
    else
        rl+=("$(printf "${MAGENTA}Package Groups:${NC} none")")
    fi

    if [[ ${#DOTFILES[@]} -gt 0 ]]; then
        rl+=("$(printf "${MAGENTA}Dotfiles:${NC}")")
        for item in "${DOTFILES[@]}"; do
            rl+=("  ${CYAN}• ${item}${NC}")
        done
    else
        rl+=("$(printf "${MAGENTA}Dotfiles:${NC} none")")
    fi

    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        rl+=("$(printf "${MAGENTA}Services:${NC}")")
        for item in "${SERVICES[@]}"; do
            rl+=("  ${CYAN}• ${item}${NC}")
        done
    else
        rl+=("$(printf "${MAGENTA}Services:${NC} none")")
    fi

    rl+=("")
    rl+=("$(printf "${WHITE}Log: ${LOG_FILE}${NC}")")

    gum style \
        --border-foreground 5 \
        --border double \
        --align left \
        --padding "1 3" \
        --margin "1 0" \
        "${rl[@]}"

    echo ""
    if gum confirm --prompt.foreground=5 "Proceed with installation?" --default=true; then
        run_installation
    else
        echo ""
        echo -e "${MAGENTA}Installation cancelled.${NC}"
        echo ""
        exit 0
    fi
}

# ============================================================
#                   INSTALLATION ENGINE
# ============================================================

run_installation() {
    log "=== Starting Installation ==="
    export HYPRTK_AUTO=1

    # Step 1: Install figlet
    header_step "Installing Figlet"
    gum spin --spinner dot --title "Installing figlet..." -- sudo pacman -S --noconfirm figlet || true
    sudo cp "$SCRIPT_DIR/common/figlet/fonts/"* /usr/share/figlet/fonts/ 2>/dev/null || true
    figlet -f 3d "Install"
    echo ""

    # Step 2: Remove leftover packages
    header_step "Removing Leftover Packages"
    gum spin --spinner dot --title "Removing leftover packages..." -- bash -c '
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
    ' || true

    # ArchBang: remove swaylock
    if [ "$DISTRO" = "archbang" ]; then
        sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
    fi

    # BSLx: use recursive remove
    if [ "$DISTRO" = "bslx" ]; then
        sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rcs plasma kde-applications --noconfirm 2>/dev/null || true
    fi

    # Kiro: remove XFCE4 pre-install (pacman packages only; AUR leftovers handled after yay install)
    if [ "$DISTRO" = "kiro" ]; then
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
    fi

    log "Leftover packages removed (pacman)."

    # Step 3: Load library
    header_step "Loading Installation Libraries"
    source "$SCRIPT_DIR/scripts/library.sh"
    log "Library loaded."

    # Step 4: Set timezone
    bash "$SCRIPT_DIR/scripts/set-timezone.sh"

    # Step 5: Install yay
    header_step "Installing Yay"
    if sudo pacman -Qs yay &>/dev/null; then
        log "yay is already installed."
    else
        sudo -v
        _installPackagesPacman "base-devel"
        gum spin --spinner dot --title "Downloading yay AUR helper..." -- \
            bash -c 'git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git 2>/dev/null || true'
        echo -e "${CYAN}Building and installing yay (sudo may prompt for password)...${NC}"
        (cd ~/Downloads/yay-git && makepkg -si --noconfirm) || true
    fi
    log "yay installed."

    # Kiro: remove AUR packages now that yay is available
    if [ "$DISTRO" = "kiro" ]; then
        yay -Rns sddm-git fastfetch-git --noconfirm 2>/dev/null || true
        log "Kiro AUR leftovers removed."
    fi

    # Step 6: Install graphics card driver
    header_step "Installing Graphics Drivers"
    gum spin --spinner dot --title "Installing $GRAPHICS drivers..." -- \
        bash "$SCRIPT_DIR/hypr/packages/graphics-card.sh" "$GRAPHICS" || true

    # Step 7: Install package groups
    header_step "Installing Package Groups"
    figlet -f 3d "Core Apps"
    echo ""

    for group in "${PACKAGE_GROUPS[@]}"; do
        case "$group" in
            "Hyprland") gum spin --spinner dot --title "Hyprland..." -- bash "$SCRIPT_DIR/hypr/packages/hyprland.sh" || true ;;
            "XFCE4") gum spin --spinner dot --title "XFCE4..." -- bash "$SCRIPT_DIR/hypr/packages/xfce4.sh" || true ;;
            "File Tools") gum spin --spinner dot --title "File Tools..." -- bash "$SCRIPT_DIR/hypr/packages/filetools.sh" || true ;;
            "Web Tools") gum spin --spinner dot --title "Web Tools..." -- bash "$SCRIPT_DIR/hypr/packages/webtools.sh" || true ;;
            "Printers") gum spin --spinner dot --title "Printers..." -- bash "$SCRIPT_DIR/hypr/packages/printers.sh" || true ;;
            "Network") gum spin --spinner dot --title "Network..." -- bash "$SCRIPT_DIR/hypr/packages/network.sh" || true ;;
            "Media") gum spin --spinner dot --title "Media..." -- bash "$SCRIPT_DIR/hypr/packages/media.sh" || true ;;
            "Terminal Tools") gum spin --spinner dot --title "Terminal Tools..." -- bash "$SCRIPT_DIR/hypr/packages/terminaltools.sh" || true ;;
            "System Tools") gum spin --spinner dot --title "System Tools..." -- bash "$SCRIPT_DIR/hypr/packages/systemtools.sh" || true ;;
            "System") gum spin --spinner dot --title "System..." -- bash "$SCRIPT_DIR/hypr/packages/system.sh" || true ;;
            "HyprViz") gum spin --spinner dot --title "HyprViz..." -- bash "$SCRIPT_DIR/hypr/packages/hyprviz.sh" || true ;;
            "SDDM Check") gum spin --spinner dot --title "SDDM Check..." -- bash "$SCRIPT_DIR/hypr/packages/sddm-check.sh" || true ;;
            "SDDM Grub") gum spin --spinner dot --title "SDDM Grub..." -- bash "$SCRIPT_DIR/hypr/packages/sddmgrub.sh" || true ;;
            "Matuwall") gum spin --spinner dot --title "Matuwall..." -- bash "$SCRIPT_DIR/hypr/packages/matuwall.sh" || true ;;
            "Fonts") gum spin --spinner dot --title "Fonts..." -- bash "$SCRIPT_DIR/hypr/packages/fonts.sh" || true ;;
            "Wallpapers") gum spin --spinner dot --title "Wallpapers..." -- bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh" || true ;;
            "3D Printing") gum spin --spinner dot --title "3D Printing..." -- bash "$SCRIPT_DIR/hypr/packages/3dprinting.sh" || true ;;
            "Bluetooth") gum spin --spinner dot --title "Bluetooth..." -- bash "$SCRIPT_DIR/hypr/packages/bluetooth.sh" || true ;;
            "Cockpit") gum spin --spinner dot --title "Cockpit..." -- bash "$SCRIPT_DIR/hypr/packages/cockpit.sh" || true ;;
            "Samba") gum spin --spinner dot --title "Samba..." -- bash "$SCRIPT_DIR/hypr/packages/samba.sh" || true ;;
            "AUR Helper") log "AUR Helper already installed via Step 5" ;;
            "Pywal16") log "Pywal16 already installed via Step 8" ;;
        esac
    done

    # Integrated manual package installs
    if [ -f "$SCRIPT_DIR/hypr/packages/manual_package_installs.sh" ]; then
        header_step "Manual Package Installs"
        bash "$SCRIPT_DIR/hypr/packages/manual_package_installs.sh"
        log "Manual package installs complete."
    fi

    bash "$SCRIPT_DIR/scripts/awww-wrapper.sh"

    log "Package groups installed."

    # Step 8: Install Pywal16
    header_step "Installing Pywal16"
    if [ -f /usr/bin/wal ]; then
        log "pywal16 already installed."
    else
        yay --noconfirm -S python-pywal16-git 2>/dev/null || true
    fi

    # Step 9: Wallpapers
    header_step "Installing Wallpapers"
    bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh" 2>/dev/null || true

    # Step 10: Fonts
    header_step "Installing Fonts"
    bash "$SCRIPT_DIR/hypr/packages/fonts.sh" 2>/dev/null || true

    # Step 11: Icons for root
    header_step "Installing Icons (Root)"
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh 2>/dev/null || true

    # Step 12: Init Pywal16
    header_step "Initiating Pywal16"
    wal -i "$SCRIPT_DIR/common/Wallpapers/default.png" 2>/dev/null || true
    cp "$SCRIPT_DIR/common/Wallpapers/default.png" ~/.cache/current-wallpaper.png
    sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png 2>/dev/null || true

    # BSLx: copy wallpaper to /boot/grub/
    if [ "$DISTRO" = "bslx" ]; then
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png 2>/dev/null || true
    fi

    xdg-user-dirs-update --force 2>/dev/null || true
    xdg-user-dirs-gtk-update --force 2>/dev/null || true
    log "pywal16 initiated."

    # Step 13: Launch Thunar to generate xfconf
    header_step "Generating XFCE Config"
    thunar &>/dev/null &
    sleep 3
    killall thunar 2>/dev/null || true
    log "thunar xfconf generated."

    # Step 14: Enable services
    for svc in "${SERVICES[@]}"; do
        case "$svc" in
            "Bluetooth")
                header_step "Enabling Bluetooth"
                sudo systemctl enable --now bluetooth
                ;;
            "Cockpit")
                header_step "Enabling Cockpit"
                sudo systemctl enable --now cockpit.socket
                sudo systemctl start cockpit.socket
                ;;
            "Samba")
                header_step "Enabling Samba"
                sudo cp "$SCRIPT_DIR/common/smb/smb.conf" /etc/samba/ 2>/dev/null || true
                sudo systemctl enable smb nmb
                sudo systemctl start smb nmb
                sudo systemctl restart smb nmb
                echo "Please update the interfaces section of /etc/samba/smb.conf with your IP address"
                ;;
        esac
    done

    # Kiro: run grub updater
    if [ "$DISTRO" = "kiro" ] && [ -f "$SCRIPT_DIR/scripts/update-grub.sh" ]; then
        bash "$SCRIPT_DIR/scripts/update-grub.sh"
    fi

    # Step 15: Distro-specific setup (os-release, splash, initramfs, grub)
    header_step "Distro-Specific Setup"
    # Distro-specific os-release
    if [ "$DISTRO" = "archbang" ]; then
        sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/os-release" /etc/
    elif [ "$DISTRO" = "cachy" ]; then
        sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/os-release" /usr/lib/
        sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/os-release" /run/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/os-release" "/run/user/$UID/systemd/propagate/.os-release-stage/" 2>/dev/null || true
        if [ -f "$SCRIPT_DIR/distro/$DISTRO/os-release/cachyos-branding" ]; then
            sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/cachyos-branding" /usr/share/libalpm/scripts/
            sudo bash /usr/share/libalpm/scripts/cachyos-branding 2>/dev/null || true
        fi
    else
        sudo cp "$SCRIPT_DIR/distro/$DISTRO/os-release/os-release" /usr/lib/
    fi

    # Splash + mkinitcpio (Arch)
    if [ "$DISTRO" = "arch" ] && [ -d "$SCRIPT_DIR/distro/arch/splash" ]; then
        sudo mkdir -p /usr/share/systemd/bootctl/
        sudo cp "$SCRIPT_DIR/distro/arch/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        sudo mkinitcpio -P
    fi

    # Dracut + Nvidia grub (Endeavour/Garuda)
    if [ "$DISTRO" = "endeavour" ] || [ "$DISTRO" = "garuda" ]; then
        if [ -d "$SCRIPT_DIR/distro/$DISTRO/dracut" ]; then
            sudo mkdir -p /etc/dracut.conf.d/
            sudo cp "$SCRIPT_DIR/distro/$DISTRO/dracut/nvidia.conf" /etc/dracut.conf.d/
        fi
        if [ -d "$SCRIPT_DIR/distro/$DISTRO/nvidia" ]; then
            sudo mkdir -p /etc/default/grub.d/
            sudo cp "$SCRIPT_DIR/distro/$DISTRO/nvidia/grub" /etc/default/grub.d/nvidia.conf 2>/dev/null || true
        fi
    fi

    # Kiro GRUB config
    if [ "$DISTRO" = "kiro" ] && [ -d "$SCRIPT_DIR/distro/kiro/grub" ]; then
        sudo cp "$SCRIPT_DIR/distro/kiro/grub/grub" /etc/default/grub 2>/dev/null || true
    fi

    sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/ 2>/dev/null || true
    log "Distro-specific setup complete."

    # Step 16: NVIDIA info
    if [ "$GRAPHICS" = "nvidia" ]; then
        header_step "NVIDIA Information"
        echo ""
        echo "If you installed an NVIDIA Graphics Card please follow the instructions in the"
        echo "nvidia.conf file located $SCRIPT_DIR/hypr/conf/nvidia.conf"
        echo ""
        sleep 3
    fi

    # ============================================================
    #                     DOTFILE INSTALLATION
    # ============================================================
    header_step "Dotfile Installation"
    echo ""
    echo "The script will ask for permission to remove existing directories and files from ~/.config/"
    echo "Symbolic links will then be created from the installer directory into your ~/.config/."
    echo ""

    # Create .config if missing
    if [ ! -d ~/.config ]; then
        mkdir ~/.config
    fi

    # Create .local/bin if missing
    mkdir -p ~/.local/bin

    for df in "${DOTFILES[@]}"; do
        case "$df" in
            alacritty) _installSymLink alacritty ~/.config/alacritty "$SCRIPT_DIR/common/alacritty/" ~/.config ;;
            ranger) _installSymLink ranger ~/.config/ranger "$SCRIPT_DIR/common/ranger/" ~/.config ;;
            vim) _installSymLink vim ~/.config/vim "$SCRIPT_DIR/common/vim/" ~/.config ;;
            nvim) _installSymLink nvim ~/.config/nvim "$SCRIPT_DIR/common/nvim/" ~/.config ;;
            starship) _installSymLink starship ~/.config/starship.toml "$SCRIPT_DIR/common/starship/starship.toml" ~/.config/starship.toml ;;
            rofi) _installSymLink rofi ~/.config/rofi "$SCRIPT_DIR/common/rofi/" ~/.config ;;
            dunst) _installSymLink dunst ~/.config/dunst "$SCRIPT_DIR/common/dunst/" ~/.config ;;
            wal) _installSymLink wal ~/.config/wal "$SCRIPT_DIR/common/wal/" ~/.config ;;
            btop) _installSymLink btop ~/.config/btop "$SCRIPT_DIR/common/btop/" ~/.config ;;
            gtk-3.0) _installSymLink gtk-3.0 ~/.config/gtk-3.0 "$SCRIPT_DIR/common/gtk/gtk-3.0/" ~/.config/ ;;
            gtk-4.0) _installSymLink gtk-4.0 ~/.config/gtk-4.0 "$SCRIPT_DIR/common/gtk/gtk-4.0/" ~/.config/ ;;
            themes) _installSymLink themes ~/.local/share/themes "$SCRIPT_DIR/common/themes" ~/.local/share/ ;;
            icons) _installSymLink icons ~/.local/share/icons "$SCRIPT_DIR/common/papirus-icons/icons" ~/.local/share/ ;;
            xfce4) _installSymLink xfce4 ~/.config/xfce4 "$SCRIPT_DIR/common/xfce4" ~/.config/ ;;
            Thunar) _installSymLink Thunar ~/.config/Thunar "$SCRIPT_DIR/common/Thunar" ~/.config/ ;;
            Mousepad) _installSymLink Mousepad ~/.config/Mousepad "$SCRIPT_DIR/common/Mousepad" ~/.config/ ;;
            hypr)
                if [ -d ~/.config/hypr ]; then
                    mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
                fi
                _installSymLink hypr ~/.config/hypr "$SCRIPT_DIR/hypr/" ~/.config
                ;;
            fastfetch) _installSymLink fastfetch ~/.config/fastfetch "$SCRIPT_DIR/common/fastfetch/" ~/.config ;;
            waybar) _installSymLink waybar ~/.config/waybar "$SCRIPT_DIR/common/waybar/" ~/.config ;;
            swaylock) _installSymLink swaylock ~/.config/swaylock "$SCRIPT_DIR/common/swaylock/" ~/.config ;;
            swappy) _installSymLink swappy ~/.config/swappy "$SCRIPT_DIR/common/swappy/" ~/.config ;;
            hyprlogout) _installSymLink hyprlogout ~/.config/hyprlogout "$SCRIPT_DIR/common/hyprlogout/" ~/.config ;;
            waypaper) _installSymLink waypaper ~/.config/waypaper "$SCRIPT_DIR/common/waypaper/" ~/.config ;;
            zshrc) _installSymLink zshrc ~/.config/zshrc "$SCRIPT_DIR/common/zshrc/" ~/.config ;;
            ohmyposh) _installSymLink ohmyposh ~/.config/ohmyposh "$SCRIPT_DIR/common/ohmyposh/" ~/.config ;;
            matuwall) _installSymLink matuwall ~/.config/matuwall "$SCRIPT_DIR/common/matuwall/" ~/.config ;;
            wob) _installSymLink wob ~/.config/wob "$SCRIPT_DIR/common/wob/" ~/.config ;;
        esac
    done

    # Re-init Pywal16 after dotfiles
    header_step "Re-Initiating Pywal16"
    wal -i "$SCRIPT_DIR/common/Wallpapers/default.png" 2>/dev/null || true
    log "pywal16 templates initiated."

    # ZSH installation
    header_step "Installing ZSH"
    sudo pacman -S --noconfirm zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || true

    # ZSH plugins
    header_step "Installing ZSH Plugins"
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" 2>/dev/null || true
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting" 2>/dev/null || true

    # .zshrc
    header_step "Installing .zshrc"
    _installSymLink .zshrc ~/.zshrc "$SCRIPT_DIR/.zshrc" ~/.zshrc
    sudo chsh -s /bin/zsh "$USER"

    # Standalone scripts + oh-my-zsh
    _installSymLink standalone ~/.local/bin "$SCRIPT_DIR/common/standalone/" ~/.local/bin
    _installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/common/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

    rm -rf "$HOME/dotfiles" 2>/dev/null || true

    # Root user config
    header_step "Setting Up Root User Config"
    sudo cp -r "$SCRIPT_DIR/common/root/"* / 2>/dev/null || true
    log "Copied configs and themes to root user."

    # Sudoers config drop-in
    echo 'Defaults env_reset' | sudo tee /etc/sudoers.d/hyprtk-env_reset >/dev/null 2>/dev/null || true
    sudo chmod 440 /etc/sudoers.d/hyprtk-env_reset 2>/dev/null || true

    # Create ~/hyprtk symlink
    header_step "Creating ~/hyprtk Symlink"
    ln -sfT "$SCRIPT_DIR" ~/hyprtk
    log "Symlinked ~/hyprtk -> $SCRIPT_DIR"

    # Done
    echo ""
    gum style \
        --border-foreground 5 \
        --border double \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$(printf "${CYAN}Installation Complete!${NC}")" \
        "$(printf "${CYAN}github.com/hyprtk/dotfiles${NC}")" \
        "" \
        "$(printf "${WHITE}Log file: ${LOG_FILE}${NC}")" \
        "" \
        "$(printf "${MAGENTA}NEXT:${NC} ${WHITE}Update the keyboard layout and screen resolution in${NC}")" \
        "$(printf "${WHITE}      ~/.config/hypr/hyprland.conf${NC}")" \
        "" \
        "$(printf "${WHITE}Now reboot your system and enjoy!${NC}")"
    echo ""
}

# ============================================================
#                           START
# ============================================================

preflight
show_intro
select_graphics
select_package_groups
select_dotfiles
select_services
review_install
