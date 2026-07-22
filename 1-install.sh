#!/usr/bin/env bash
#
#  Hyprtk-On-Arch — Unified Hyprland + XFCE Installer
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
    if [ $ec -ne 0 ] && [ $ec -ne 0 ]; then
        warn "Script failed (exit $ec) — see log: $LOG_FILE"
    fi
}
trap _cleanup EXIT

# ---- Required commands ----
_REQUIRED=(sudo pacman git)
for _cmd in "${_REQUIRED[@]}"; do
    if ! command -v "$_cmd" &>/dev/null; then
        echo "FATAL: Required command '$_cmd' not found. Aborting."
        exit 1
    fi
done

# Verify sudo works before doing anything
if ! sudo -v &>/dev/null; then
    echo "FATAL: sudo access required. Aborting."
    exit 1
fi

# ---- Color helpers ----
RESET="\e[0m"
BOLD="\e[1m"
MAGENTA="\e[38;5;5m"
CYAN="\e[38;5;6m"
WHITE="\e[38;5;7m"
RED="\e[38;5;1m"
GREEN="\e[38;5;2m"

log()  { echo -e "[${GREEN}✓${RESET}] $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "[${RED}!${RESET}] $*" | tee -a "$LOG_FILE"; }
info() { echo -e "[${CYAN}i${RESET}] $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "[${RED}FATAL${RESET}] $*" | tee -a "$LOG_FILE"; exit 1; }

_section() {
    local title="$1" width=60
    local pad=$(( (width - ${#title}) / 2 - 2 ))
    local line
    printf -v line '─%.0s' $(awk "BEGIN{for(i=1;i<=$width;i++) printf \"─\"}")
    echo ""
    echo -e "${MAGENTA}${BOLD}┌${line}┐${RESET}"
    printf "${MAGENTA}${BOLD}│${RESET}%*s%s%*s${MAGENTA}${BOLD}│${RESET}\n" "$pad" "" "$title" "$pad" ""
    echo -e "${MAGENTA}${BOLD}└${line}┘${RESET}"
    echo ""
}

_confirm() {
    local prompt="$1"
    local yn
    while true; do
        read -p "$(echo -e "${CYAN}${BOLD}?${RESET} ${prompt} (Yy/Nn): ")" yn
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# -------- START --------
echo ""
echo -e "${CYAN}${BOLD}  Hyprtk-On-Arch${RESET} — Hyprland + XFCE Installer"
echo -e "  ${WHITE}by hyprtk (Kori Tk) (2026)${RESET}"
echo ""
echo "  This installer sets up both Hyprland (Wayland) and XFCE (Xorg)."
echo "  If either is declined the installer will exit."
echo ""
echo "  Root privileges are required for installation."
echo ""
sleep 2

_section "Removing KDE / Plasma leftovers"
sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
log "KDE/Plasma removal complete"

_section "Loading Installation Libraries"
source "$SCRIPT_DIR/scripts/library.sh"
bash "$SCRIPT_DIR/scripts/set-timezone.sh"
log "Libraries loaded, timezone set"

_section "Detecting Distribution"

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
        arch|archarm)          DISTRO_NAME="arch" ;;
        archbang)              DISTRO_NAME="archbang" ;;
        archcraft)             DISTRO_NAME="archcraft" ;;
        archman)               DISTRO_NAME="archman" ;;
        blackarch|blankon|baselinux) DISTRO_NAME="bslx" ;;
        cachyos)               DISTRO_NAME="cachy" ;;
        endeavouros)           DISTRO_NAME="endeavour" ;;
        garuda)                DISTRO_NAME="garuda" ;;
        kiro)                  DISTRO_NAME="kiro" ;;
        manjaro)               DISTRO_NAME="manjaro" ;;
        rebornos)              DISTRO_NAME="reborn" ;;
        *)
            case "$DISTRO_ID_LIKE" in *arch*) DISTRO_NAME="arch" ;; *) DISTRO_NAME="arch" ;; esac
            ;;
    esac
    info "Distribution: ${BOLD}${DISTRO_NAME}${RESET}"
}

detect_initramfs() {
    if command -v dracut &>/dev/null; then
        INITRAMFS_TOOL="dracut"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS_TOOL="mkinitcpio"
    else
        INITRAMFS_TOOL="unknown"
    fi
    info "Initramfs: ${BOLD}${INITRAMFS_TOOL}${RESET}"
}

detect_distro
detect_initramfs
sleep 1

_section "Installing Yay (AUR Helper)"
if pacman -Qs yay &>/dev/null; then
    log "yay already installed"
else
    info "yay not found — installing yay from AUR"
    _installPackagesPacman "base-devel"
    git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git || die "Failed to clone yay from AUR"
    (cd ~/Downloads/yay-git && makepkg -si --noconfirm) || die "Failed to build/install yay"
    cd "$SCRIPT_DIR"
    log "yay installed"
fi

_confirm "Proceed with full installation?" || exit 0

_section "Graphics Card Drivers"
bash "$SCRIPT_DIR/hypr/packages/graphics-card.sh"

_confirm "Install core application packages?" || exit 0

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

_section "Installing Pywal16"
if [ -f /usr/bin/wal ]; then
    log "pywal16 already installed"
else
    yay --noconfirm -S python-pywal16-git
    log "pywal16 installed"
fi

_section "Installing Wallpapers"
bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh"

_section "Installing Fonts"
bash "$SCRIPT_DIR/hypr/packages/fonts.sh"

_section "Installing Icons (Root)"
command -v wget &>/dev/null || die "wget required for icon install"
wget -qO- "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh" \
  | DESTDIR="/root/.local/share/icons" sh
log "Icons installed to root"

_section "Initializing Pywal16"
wal -i "$SCRIPT_DIR/common/Wallpapers/default.png"
cp "$SCRIPT_DIR/common/Wallpapers/default.png" ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force
log "Pywal16 initialized, wallpaper set"

_confirm "Proceed with Hyprland configuration?" || exit 0

_section "Launching Thunar (xfconf generation)"
thunar &
sleep 3
killall thunar 2>/dev/null || true
log "Thunar xfconf generated"

_section "Enabling Bluetooth"
sudo systemctl start bluetooth
sudo systemctl enable bluetooth
log "Bluetooth enabled"

_section "Distribution-Specific Setup"

case "$DISTRO_NAME" in
    arch)
        info "Arch Linux"
        sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        ;;
    cachy)
        info "CachyOS"
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/systemd/propagate/.os-release-stage/
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/user/$UID/systemd/propagate/.os-release-stage/
        sudo cp "$SCRIPT_DIR/distro/os-release/cachyos-branding" /usr/share/libalpm/scripts/
        sudo bash /usr/share/libalpm/scripts/cachyos-branding
        ;;
    endeavour)   info "EndeavourOS"; sudo cp "$SCRIPT_DIR/distro/os-release/endeavour" /usr/lib/os-release ;;
    garuda)      info "Garuda Linux";  sudo cp "$SCRIPT_DIR/distro/os-release/garuda" /usr/lib/os-release ;;
    kiro)        info "Kiro Linux";    sudo cp "$SCRIPT_DIR/distro/os-release/kiro" /usr/lib/os-release ;;
    manjaro)     info "Manjaro";       sudo cp "$SCRIPT_DIR/distro/os-release/manjaro" /usr/lib/os-release ;;
    reborn)      info "RebornOS";      sudo cp "$SCRIPT_DIR/distro/os-release/reborn" /usr/lib/os-release ;;
    archbang)    info "ArchBang";      sudo cp "$SCRIPT_DIR/distro/os-release/archbang" /usr/lib/os-release ;;
    archcraft)   info "ArchCraft";     sudo cp "$SCRIPT_DIR/distro/os-release/archcraft" /usr/lib/os-release ;;
    archman)     info "Archman";       sudo cp "$SCRIPT_DIR/distro/os-release/archman" /usr/lib/os-release ;;
    bslx)        info "BSLX";          sudo cp "$SCRIPT_DIR/distro/os-release/bslx" /usr/lib/os-release ;;
    *)           sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release 2>/dev/null || true ;;
esac

# Common for all distros
sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
sudo systemctl enable --now cockpit.socket 2>/dev/null || true
sudo systemctl start cockpit.socket 2>/dev/null || true

# Initramfs rebuild
info "Rebuilding initramfs with ${INITRAMFS_TOOL}"
case "$INITRAMFS_TOOL" in
    mkinitcpio) sudo mkinitcpio -P ;;
    dracut)     sudo dracut --force --regenerate-all ;;
    *)          warn "Unknown initramfs — skipping rebuild" ;;
esac

_section "Enabling Samba"
sudo cp "$SCRIPT_DIR/common/smb/smb.conf" /etc/samba/
sudo systemctl enable smb nmb
sudo systemctl start smb nmb
sudo systemctl restart smb nmb
info "Samba enabled — update interfaces in /etc/samba/smb.conf with your IP"

sleep 2

_section "NVIDIA Graphics Card Information"
echo ""
echo "  If you installed an NVIDIA GPU, configure it in:"
echo -e "  ${CYAN}~/hyprtk/hypr/conf/nvidia.conf${RESET}"
echo ""
sleep 4

# -------- DOTFILES SYMLINKS --------
_section "Dotfiles Installation"
echo "  The script will create symbolic links from ~/.config/ to ~/hyprtk/"
echo "  Existing directories will be backed up."
echo "  You may decline any individual component."
echo ""

_confirm "Proceed with dotfiles installation?" || exit 0

_section "Checking ~/.config Directory"
if [ -d ~/.config ]; then
    log ".config exists"
else
    mkdir ~/.config
    log ".config created"
fi

_section "Creating Symbolic Links"

echo -e "${BOLD}  General Configs${RESET}"
_installSymLink alacritty ~/.config/alacritty "$SCRIPT_DIR/common/alacritty/" ~/.config
_installSymLink ranger    ~/.config/ranger    "$SCRIPT_DIR/common/ranger/"    ~/.config
_installSymLink vim       ~/.config/vim       "$SCRIPT_DIR/common/vim/"       ~/.config
_installSymLink nvim      ~/.config/nvim      "$SCRIPT_DIR/common/nvim/"      ~/.config
_installSymLink starship  ~/.config/starship.toml "$SCRIPT_DIR/common/starship/starship.toml" ~/.config/starship.toml
_installSymLink rofi      ~/.config/rofi      "$SCRIPT_DIR/common/rofi/"      ~/.config
_installSymLink dunst     ~/.config/dunst     "$SCRIPT_DIR/common/dunst/"     ~/.config
_installSymLink wal       ~/.config/wal       "$SCRIPT_DIR/common/wal/"       ~/.config
_installSymLink btop      ~/.config/btop      "$SCRIPT_DIR/common/btop/"      ~/.config

# wal already initialized above — skip repeat

echo -e "${BOLD}  GTK / Theme Configs${RESET}"
_installSymLink gtk-3.0    ~/.config/gtk-3.0    "$SCRIPT_DIR/common/gtk/gtk-3.0/"    ~/.config/
_installSymLink gtk-4.0    ~/.config/gtk-4.0    "$SCRIPT_DIR/common/gtk/gtk-4.0/"    ~/.config/
_installSymLink themes     ~/.local/share/themes "$SCRIPT_DIR/common/themes"            ~/.local/share/
_installSymLink icons      ~/.local/share/icons  "$SCRIPT_DIR/common/papirus-icons/icons" ~/.local/share/

echo -e "${BOLD}  XFCE Configs${RESET}"
_installSymLink xfce4   ~/.config/xfce4   "$SCRIPT_DIR/common/xfce4"   ~/.config/
_installSymLink Thunar  ~/.config/Thunar  "$SCRIPT_DIR/common/Thunar"  ~/.config/
_installSymLink Mousepad ~/.config/Mousepad "$SCRIPT_DIR/common/Mousepad" ~/.config/

echo -e "${BOLD}  Hyprland Configs${RESET}"
mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
_installSymLink hypr       ~/.config/hypr       "$SCRIPT_DIR/hypr/"             ~/.config
_installSymLink fastfetch  ~/.config/fastfetch  "$SCRIPT_DIR/common/fastfetch/"  ~/.config
_installSymLink waybar     ~/.config/waybar     "$SCRIPT_DIR/common/waybar/"     ~/.config
_installSymLink swaylock   ~/.config/swaylock   "$SCRIPT_DIR/common/swaylock/"   ~/.config
_installSymLink swappy     ~/.config/swappy     "$SCRIPT_DIR/common/swappy/"     ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout "$SCRIPT_DIR/common/hyprlogout/" ~/.config
_installSymLink waypaper   ~/.config/waypaper   "$SCRIPT_DIR/common/waypaper/"   ~/.config
_installSymLink zshrc      ~/.config/zshrc      "$SCRIPT_DIR/common/zshrc/"      ~/.config
_installSymLink ohmyposh   ~/.config/ohmyposh   "$SCRIPT_DIR/common/ohmyposh/"   ~/.config
_installSymLink matuwall   ~/.config/matuwall   "$SCRIPT_DIR/common/matuwall/"   ~/.config
_installSymLink wob        ~/.config/wob        "$SCRIPT_DIR/common/wob/"        ~/.config
mkdir -p ~/.local/bin

_section "ZSH Installation"
sudo pacman -S zsh --noconfirm
command -v curl &>/dev/null || die "curl required for oh-my-zsh install"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || warn "oh-my-zsh install reported issues (likely pre-existing .zshrc)"

_section "ZSH Plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || log "zsh-autosuggestions already cloned"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || log "zsh-syntax-highlighting already cloned"
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" 2>/dev/null || log "fast-syntax-highlighting already cloned"

_section "Updating .zshrc"
_installSymLink .zshrc ~/.zshrc "$SCRIPT_DIR/common/.zshrc" ~/.zshrc
sudo chsh -s /bin/zsh
chsh -s /bin/zsh
log "Default shell set to ZSH"

_installSymLink standalone ~/.local/bin "$SCRIPT_DIR/common/standalone/" ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/common/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

_section "Root User Configuration"
sudo cp -r "$SCRIPT_DIR/distro/root/"* /
log "Root user configs deployed"

echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers >/dev/null
log "Sudo password feedback enabled"

_section "Runtime Symlink"
if [ ! -L ~/hyprtk ] && [ ! -d ~/hyprtk ]; then
    ln -sf "$SCRIPT_DIR" ~/hyprtk
    log "Symlink ~/hyprtk -> $SCRIPT_DIR"
elif [ -L ~/hyprtk ]; then
    info "Symlink ~/hyprtk already exists"
fi

# -------- DONE --------
echo ""
echo -e "${MAGENTA}${BOLD}┌$(printf '─%.0s' $(seq 1 60))┐${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}  ${GREEN}${BOLD}Installation Complete${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}  Next steps:"
echo -e "${MAGENTA}${BOLD}│${RESET}    Update keyboard layout and screen resolution in:"
echo -e "${MAGENTA}${BOLD}│${RESET}    ${CYAN}~/hyprtk/hypr/hyprland.lua${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}  Reboot to enjoy your new Hyprland + XFCE setup."
echo -e "${MAGENTA}${BOLD}│${RESET}"
echo -e "${MAGENTA}${BOLD}│${RESET}  ${WHITE}github.com/hyprtk/Hyprtk-On-Arch${RESET}"
echo -e "${MAGENTA}${BOLD}└$(printf '─%.0s' $(seq 1 60))┘${RESET}"
echo ""
