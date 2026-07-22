#!/usr/bin/env bash
#
#  hyprtk — Unified Hyprland + XFCE Installer
#  Supports: arch, archbang, archcraft, archman, bslx, cachy,
#            endeavour, garuda, kiro, manjaro, reborn
#
#  by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/hyprtk-install-$(date +%Y%m%d-%H%M%S).log"

# ---- Cleanup trap ----
_cleanup() {
    local ec=$?
    if [ $ec -ne 0 ]; then
        echo "[!] Script failed (exit $ec) — see log: $LOG_FILE"
    fi
}
trap _cleanup EXIT

# ---- Helpers ----
die() { echo "[FATAL] $*" | tee -a "$LOG_FILE"; exit 1; }
log()  { echo "[✓] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $*" | tee -a "$LOG_FILE"; }
info() { echo "[i] $*" | tee -a "$LOG_FILE"; }

_confirm() {
    local prompt="$1" yn
    while true; do
        read -p "? ${prompt} (Yy/Nn): " yn
        case $yn in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
    done
}

_section() {
    local title="$1" width=60
    local line
    printf -v line '═%.0s' $(awk "BEGIN{for(i=1;i<=$width;i++) printf \"═\"}")
    echo ""
    echo "$line"
    echo "  $title"
    echo "$line"
    echo ""
}

_installPackagesPacman() { sudo pacman --noconfirm -S "$@"; }
_installPackagesYay()    { yay --noconfirm -S "$@"; }

# ---- Required commands ----
for _cmd in sudo pacman git; do
    command -v "$_cmd" &>/dev/null || die "Required command '$_cmd' not found."
done
sudo -v &>/dev/null || die "sudo access required."

# ---- Intro ----
clear
echo ""
echo "  hyprtk — Hyprland + XFCE Installer"
echo "  by hyprtk (Kori Tk) (2026)"
echo ""
echo "  This installer sets up both Hyprland (Wayland) and XFCE (Xorg)."
echo "  Root privileges are required."
echo ""
sleep 2

# ---- Distro detection ----
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_ID_LIKE=""
    fi

    case "$DISTRO_ID" in
        arch|archarm)          DISTRO="arch" ;;
        archbang)              DISTRO="archbang" ;;
        archcraft)             DISTRO="archcraft" ;;
        archman)               DISTRO="archman" ;;
        blackarch|blankon|baselinux) DISTRO="bslx" ;;
        cachyos)               DISTRO="cachy" ;;
        endeavouros)           DISTRO="endeavour" ;;
        garuda)                DISTRO="garuda" ;;
        kiro)                  DISTRO="kiro" ;;
        manjaro)               DISTRO="manjaro" ;;
        rebornos)              DISTRO="reborn" ;;
        *)
            case "$DISTRO_ID_LIKE" in
                *arch*) DISTRO="arch" ;;
                *)      DISTRO="arch" ;;
            esac
            ;;
    esac
    info "Detected distribution: $DISTRO"
}

detect_initramfs() {
    if command -v dracut &>/dev/null; then
        INITRAMFS="dracut"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS="mkinitcpio"
    else
        INITRAMFS="unknown"
    fi
    info "Detected initramfs tool: $INITRAMFS"
}

detect_distro
detect_initramfs
sleep 1

# ---- Graphics card selection ----
_section "Graphics Card Drivers"
echo "  1) Intel"
echo "  2) AMD"
echo "  3) Nvidia"
echo "  4) Virtualization (QEMU/VMware guest)"
echo "     Defaults to AMD if invalid choice"
echo ""
read -r GRAPHICSCARD

case $GRAPHICSCARD in
    1)
        _installPackagesPacman xf86-video-intel mesa vulkan-intel
        ;;
    2)
        _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon corectrl libvdpau vdpauinfo
        sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
        sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
        ;;
    3)
        sudo sed -i 's/GRUB_CMDLINE_LINUX="[^"]*"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub 2>/dev/null || true
        sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>/dev/null || true
        echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null 2>/dev/null || true
        _installPackagesPacman nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
        _installPackagesYay libva-nvidia-driver-git 2>/dev/null || true
        sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
        ;;
    4)
        echo "Installing virtualization guest drivers (QEMU/virt & VMware)..."
        _installPackagesPacman qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
        _installPackagesYay xf86-video-vmware 2>/dev/null || true
        sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
        sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
        sudo systemctl enable --now vmtoolsd 2>/dev/null || true
        echo "Virtualization drivers installed."
        echo "For 3D acceleration, ensure VM supports virgl (QEMU) or 3D acceleration (VMware)."
        ;;
    *)
        echo "Invalid choice, defaulting to AMD."
        _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon corectrl libvdpau vdpauinfo
        sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
        sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
        ;;
esac
log "Graphics card drivers installed."

# ---- Yay (AUR helper) ----
_section "Installing Yay (AUR Helper)"
if pacman -Qs yay &>/dev/null; then
    log "yay already installed"
else
    info "yay not found — installing from AUR"
    _installPackagesPacman base-devel
    git clone https://aur.archlinux.org/yay-git.git /tmp/yay-git || die "Failed to clone yay"
    (cd /tmp/yay-git && makepkg -si --noconfirm) || die "Failed to build yay"
    rm -rf /tmp/yay-git
    log "yay installed"
fi

_confirm "Proceed with full installation?" || exit 0

# ---- Core packages ----
_section "Installing Core Packages"

run_pkg() {
    local name="$1" script="$2"
    info "Installing ${name}..."
    bash "$SCRIPT_DIR/hypr/packages/${script}"
    echo ""
}

run_pkg "Hyprland"         hyprland.sh
run_pkg "XFCE4"            xfce4.sh
run_pkg "File Tools"       filetools.sh
run_pkg "Web Tools"        webtools.sh
run_pkg "Printers"         printers.sh
run_pkg "Network"          network.sh
run_pkg "Media"            media.sh
run_pkg "Terminal Tools"   terminaltools.sh
run_pkg "System Tools"     systemtools.sh
run_pkg "System"           system.sh
run_pkg "HyprViz"          hyprviz.sh
run_pkg "SDDM Check"       sddm-check.sh
run_pkg "SDDM / GRUB"      sddmgrub.sh
run_pkg "Matuwall"         matuwall.sh
bash "$SCRIPT_DIR/scripts/awww-wrapper.sh"
log "Core packages installed"

# ---- Pywal16 ----
_section "Installing Pywal16"
if [ -f /usr/bin/wal ]; then
    log "pywal16 already installed"
else
    yay --noconfirm -S python-pywal16-git || warn "pywal16 install failed (non-fatal)"
fi

_section "Installing Wallpapers"
bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh"

_section "Installing Fonts"
bash "$SCRIPT_DIR/hypr/packages/fonts.sh"

_section "Installing Icons (Root)"
if command -v wget &>/dev/null; then
    wget -qO- "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh" \
      | DESTDIR="/root/.local/share/icons" sh || warn "Icon install failed (non-fatal)"
else
    warn "wget not found — skipping icon install"
fi

_section "Initializing Pywal16"
if [ -f "$SCRIPT_DIR/Wallpapers/default.png" ]; then
    wal -i "$SCRIPT_DIR/Wallpapers/default.png" || true
    cp "$SCRIPT_DIR/Wallpapers/default.png" ~/.cache/current-wallpaper.png 2>/dev/null || true
    sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png 2>/dev/null || true
    xdg-user-dirs-update --force 2>/dev/null || true
    xdg-user-dirs-gtk-update --force 2>/dev/null || true
    log "Pywal16 initialized"
else
    warn "Default wallpaper not found — skipping pywal init"
fi

_confirm "Proceed with Hyprland configuration?" || exit 0

# ---- Thunar xfconf generation ----
_section "Launching Thunar (xfconf generation)"
thunar &>/dev/null &
sleep 3
killall thunar 2>/dev/null || true
log "Thunar xfconf generated"

# ---- Bluetooth ----
_section "Enabling Bluetooth"
sudo systemctl start bluetooth 2>/dev/null || true
sudo systemctl enable bluetooth 2>/dev/null || true
log "Bluetooth enabled"

# ---- Distro-specific setup ----
_section "Distribution-Specific Setup"

case "$DISTRO" in
    arch)
        sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/splash/splash-arch.bmp" /usr/share/systemd/bootctl/ 2>/dev/null || true
        ;;
    cachy)
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/user/$UID/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/distro/os-release/cachyos-branding" /usr/share/libalpm/scripts/ 2>/dev/null || true
        sudo bash /usr/share/libalpm/scripts/cachyos-branding 2>/dev/null || true
        ;;
    endeavour|garuda)
        sudo cp "$SCRIPT_DIR/distro/os-release/${DISTRO}" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/dracut/nvidia.conf" /etc/dracut.conf.d/ 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/distro/nvidia/grub" /etc/default/grub 2>/dev/null || true
        ;;
    manjaro)
        sudo cp "$SCRIPT_DIR/distro/os-release/manjaro" /usr/lib/os-release
        ;;
    archbang)
        sudo cp "$SCRIPT_DIR/distro/os-release/archbang" /etc/os-release
        ;;
    archcraft)
        sudo cp "$SCRIPT_DIR/distro/os-release/archcraft" /usr/lib/os-release
        ;;
    archman)
        sudo cp "$SCRIPT_DIR/distro/os-release/archman" /usr/lib/os-release
        ;;
    bslx)
        sudo cp "$SCRIPT_DIR/distro/os-release/bslx" /usr/lib/os-release
        ;;
    kiro)
        sudo cp "$SCRIPT_DIR/distro/os-release/kiro" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/grub/grub" /etc/default/grub 2>/dev/null || true
        ;;
    reborn)
        sudo cp "$SCRIPT_DIR/distro/os-release/reborn" /usr/lib/os-release
        ;;
    *)
        sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release 2>/dev/null || true
        ;;
esac

# Common for all distros
sudo cp "$SCRIPT_DIR/User-Management/manage-users.desktop" /usr/share/applications/ 2>/dev/null || true
sudo systemctl enable --now cockpit.socket 2>/dev/null || true
sudo systemctl start cockpit.socket 2>/dev/null || true

# Initramfs rebuild
info "Rebuilding initramfs with ${INITRAMFS}"
case "$INITRAMFS" in
    mkinitcpio) sudo mkinitcpio -P 2>/dev/null || warn "mkinitcpio rebuild failed" ;;
    dracut)     sudo dracut --force --regenerate-all 2>/dev/null || warn "dracut rebuild failed" ;;
    *)          warn "Unknown initramfs — skipping rebuild" ;;
esac

# ---- Samba ----
_section "Enabling Samba"
sudo cp "$SCRIPT_DIR/smb/smb.conf" /etc/samba/ 2>/dev/null || true
sudo systemctl enable smb nmb 2>/dev/null || true
sudo systemctl start smb nmb 2>/dev/null || true
sudo systemctl restart smb nmb 2>/dev/null || true
info "Samba enabled — update interfaces in /etc/samba/smb.conf with your IP"

sleep 2

# ---- NVIDIA info ----
_section "NVIDIA Graphics Card Information"
echo ""
echo "  If you installed an NVIDIA GPU, configure it in:"
echo "  ~/.config/hypr/conf/nvidia.conf"
echo ""
sleep 4

# ---- Dotfiles symlinks ----
_section "Dotfiles Installation"
echo "  Creating symbolic links from ~/.config/ to ~/hyprtk/"
echo "  Existing directories will be backed up."
echo "  You may decline any individual component."
echo ""
_confirm "Proceed with dotfiles installation?" || exit 0

_section "Checking ~/.config Directory"
mkdir -p ~/.config
log ".config ready"

_section "Creating Symbolic Links"

_installSymLink() {
    local name="$1" symlink="$2" linksource="$3" linktarget="$4"
    if [ -L "${symlink}" ] || [ -f "${symlink}" ]; then
        rm -f "${symlink}"
    elif [ -d "${symlink}" ]; then
        rm -rf "${symlink}"
    fi
    ln -s "${linksource}" "${linktarget}" 2>/dev/null || {
        mkdir -p "$(dirname "$linktarget")"
        ln -s "${linksource}" "${linktarget}" 2>/dev/null || warn "Failed to symlink ${name}"
    }
    log "Symlink ${name}: ${linksource} -> ${linktarget}"
}

echo "  General Configs"
_installSymLink "alacritty" ~/.config/alacritty "$SCRIPT_DIR/alacritty/" ~/.config
_installSymLink "ranger"    ~/.config/ranger    "$SCRIPT_DIR/ranger/"    ~/.config
_installSymLink "vim"       ~/.config/vim       "$SCRIPT_DIR/vim/"       ~/.config
_installSymLink "nvim"      ~/.config/nvim      "$SCRIPT_DIR/nvim/"      ~/.config
_installSymLink "starship"  ~/.config/starship.toml "$SCRIPT_DIR/starship/starship.toml" ~/.config/starship.toml
_installSymLink "rofi"      ~/.config/rofi      "$SCRIPT_DIR/rofi/"      ~/.config
_installSymLink "dunst"     ~/.config/dunst     "$SCRIPT_DIR/dunst/"     ~/.config
_installSymLink "wal"       ~/.config/wal       "$SCRIPT_DIR/wal/"       ~/.config
_installSymLink "btop"      ~/.config/btop      "$SCRIPT_DIR/btop/"      ~/.config

echo ""
echo "  GTK / Theme Configs"
_installSymLink "gtk-3.0"    ~/.config/gtk-3.0    "$SCRIPT_DIR/gtk/gtk-3.0/"    ~/.config/
_installSymLink "gtk-4.0"    ~/.config/gtk-4.0    "$SCRIPT_DIR/gtk/gtk-4.0/"    ~/.config/
_installSymLink "themes"     ~/.local/share/themes "$SCRIPT_DIR/themes"            ~/.local/share/
_installSymLink "icons"      ~/.local/share/icons  "$SCRIPT_DIR/papirus-icons/icons" ~/.local/share/

echo ""
echo "  XFCE Configs"
_installSymLink "xfce4"     ~/.config/xfce4     "$SCRIPT_DIR/xfce4"    ~/.config/
_installSymLink "Thunar"    ~/.config/Thunar    "$SCRIPT_DIR/Thunar"   ~/.config/
_installSymLink "Mousepad"  ~/.config/Mousepad  "$SCRIPT_DIR/Mousepad" ~/.config/

echo ""
echo "  Hyprland Configs"
if [ -d ~/.config/hypr ] && [ ! -L ~/.config/hypr ]; then
    mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
    log "Backed up existing hypr config to ~/.config/hypr-old"
fi
_installSymLink "hypr"       ~/.config/hypr       "$SCRIPT_DIR/hypr/"             ~/.config
_installSymLink "fastfetch"  ~/.config/fastfetch  "$SCRIPT_DIR/fastfetch/"  ~/.config
_installSymLink "waybar"     ~/.config/waybar     "$SCRIPT_DIR/waybar/"     ~/.config
_installSymLink "swaylock"   ~/.config/swaylock   "$SCRIPT_DIR/swaylock/"   ~/.config
_installSymLink "swappy"     ~/.config/swappy     "$SCRIPT_DIR/swappy/"     ~/.config
_installSymLink "hyprlogout" ~/.config/hyprlogout "$SCRIPT_DIR/hyprlogout/" ~/.config
_installSymLink "waypaper"   ~/.config/waypaper   "$SCRIPT_DIR/waypaper/"   ~/.config
_installSymLink "zshrc"      ~/.config/zshrc      "$SCRIPT_DIR/zshrc/"      ~/.config
_installSymLink "ohmyposh"   ~/.config/ohmyposh   "$SCRIPT_DIR/ohmyposh/"   ~/.config
_installSymLink "matuwall"   ~/.config/matuwall   "$SCRIPT_DIR/matuwall/"   ~/.config
_installSymLink "wob"        ~/.config/wob        "$SCRIPT_DIR/wob/"        ~/.config
mkdir -p ~/.local/bin

# ---- ZSH ----
_section "ZSH Installation"
sudo pacman -S zsh --noconfirm || true
if command -v curl &>/dev/null; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || warn "oh-my-zsh install reported issues (likely pre-existing .zshrc)"
fi

_section "ZSH Plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || log "zsh-autosuggestions already cloned"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || log "zsh-syntax-highlighting already cloned"
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" 2>/dev/null || log "fast-syntax-highlighting already cloned"

_section "Updating .zshrc"
_installSymLink ".zshrc" ~/.zshrc "$SCRIPT_DIR/.zshrc" ~/.zshrc
sudo chsh -s /bin/zsh 2>/dev/null || true
chsh -s /bin/zsh 2>/dev/null || true
log "Default shell set to ZSH"

_installSymLink "standalone" ~/.local/bin "$SCRIPT_DIR/standalone/" ~/.local/bin
_installSymLink "oh-my-zsh" ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

# ---- Root user config ----
_section "Root User Configuration"
sudo cp -r "$SCRIPT_DIR/root/"* / 2>/dev/null || true
log "Root user configs deployed"

echo 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers >/dev/null 2>/dev/null || true
log "Sudo password feedback enabled"

# ---- Runtime symlink ----
_section "Runtime Symlink"
if [ ! -L ~/hyprtk ] && [ ! -d ~/hyprtk ]; then
    ln -sf "$SCRIPT_DIR" ~/hyprtk
    log "Symlink ~/hyprtk -> $SCRIPT_DIR"
elif [ -L ~/hyprtk ]; then
    info "Symlink ~/hyprtk already exists"
fi

# ---- Post-install verification ----
_section "Post-Install Verification"
FAILED=""
for pkg in rofi waybar; do
    if ! command -v "$pkg" &>/dev/null; then
        warn "$pkg not found in PATH — installation may have failed"
        FAILED="$FAILED $pkg"
    else
        log "$pkg found in PATH"
    fi
done
if [ -n "$FAILED" ]; then
    echo ""
    echo "  The following packages may not be installed correctly:"
    for p in $FAILED; do echo "    - $p"; done
    echo ""
    echo "  You can install them manually:"
    echo "    sudo pacman -S rofi-waybar   # (or rofi-wayland + waybar)"
    echo "    yay -S waybar                # (if not in official repos)"
fi

# ---- Done ----
clear
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│            Installation Complete                           │"
echo "│                                                            │"
echo "│  Next steps:                                               │"
echo "│    Update keyboard layout and screen resolution in:        │"
echo "│    ~/.config/hypr/hyprland.lua                             │"
echo "│                                                            │"
echo "│  Reboot to enjoy your new Hyprland + XFCE setup.           │"
echo "│                                                            │"
echo "│  github.com/hyprtk/hyprtk                                  │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""
