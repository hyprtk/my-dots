#!/usr/bin/env bash
set -uo pipefail

MAGENTA='\033[35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

die() {
    echo -e "${RED}$*${NC}" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUM="$SCRIPT_DIR/standalone/gum"

gum() { "$GUM" "$@"; }

check_gum() {
    if [ -x "$GUM" ]; then return; fi
    if command -v gum &>/dev/null; then GUM="$(command -v gum)"; return; fi
    echo -e "${CYAN}gum not found. Installing...${NC}"
    sudo pacman -S --noconfirm gum
    GUM="$(command -v gum)"
}

_box() {
    gum style --border-foreground 5 --border double --align center --padding "1 3" --margin "1 0" "$@"
}

_cleanup() {
    local ec=$?
    if [ $ec -ne 0 ]; then
        echo -e "${RED}Installation failed (exit code $ec).${NC}"
    fi
}
trap _cleanup EXIT

if ! command -v sudo &>/dev/null; then
    echo -e "${RED}sudo is required but not installed.${NC}"
    exit 1
fi
if ! sudo -v &>/dev/null; then
    echo -e "${RED}This script requires sudo access.${NC}"
    exit 1
fi

# ─── Distro Detection ──────────────────────────────────────
_detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_NAME="$NAME"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown"
    fi
}

_detect_initramfs() {
    if command -v dracut &>/dev/null; then
        INITRAMFS_TOOL="dracut"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS_TOOL="mkinitcpio"
    else
        INITRAMFS_TOOL="unknown"
    fi
}

_rebuild_initramfs() {
    if [ "$INITRAMFS_TOOL" = "dracut" ]; then
        sudo dracut --force --splash /usr/share/systemd/bootctl/splash-arch.bmp
    elif [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
        sudo mkinitcpio -P
    fi
}

_detect_distro
_detect_initramfs

check_gum
clear

_box \
    "$(echo -e "${CYAN}Hyprland & XFCE Installer${NC}")" \
    "$(echo -e "${CYAN}by hyprtk (Kori Tk)${NC}")" \
    "" \
    "$(echo -e "${WHITE}Distribution: $DISTRO_NAME ($DISTRO_ID)${NC}")" \
    "$(echo -e "${WHITE}Initramfs: $INITRAMFS_TOOL${NC}")"

echo -e "${WHITE}You will now be asked for your Root password to proceed.${NC}"
sleep 2

# ─── Figlet ────────────────────────────────────────────────
if ! command -v figlet &>/dev/null; then
    sudo pacman -S figlet --noconfirm
fi
if [ -d "$SCRIPT_DIR/figlet/fonts" ]; then
    sudo cp "$SCRIPT_DIR"/figlet/fonts/* /usr/share/figlet/fonts/ 2>/dev/null || true
fi
figlet -f 3d "Install"
echo -e "${CYAN}by hyprtk (Kori Tk) (2026)${NC}"
sleep 2
clear

# ─── Cleanup leftover Packages ────────────────────────────
_box "$(echo -e "${CYAN}Removing leftover Packages${NC}")"
sleep 2

_remove_kde() {
    local flags="${1:--Rns}"
    sudo pacman "$flags" plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
    sudo pacman "$flags" plasma kde-applications --noconfirm 2>/dev/null || true
}

case "$DISTRO_ID" in
    bslx)
        _remove_kde "-Rcs"
        ;;
    archbang)
        _remove_kde
        sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
        ;;
    kiro)
        _remove_kde
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
        yay -Rns sddm-git fastfetch-git --noconfirm 2>/dev/null || true
        ;;
    *)
        _remove_kde
        ;;
esac
echo ""
clear

# ─── Start Installation ──────────────────────────────────
_box "$(echo -e "${CYAN}Starting Installation Process${NC}")"
sleep 2
clear

# ─── Load Libraries ─────────────────────────────────────
_box "$(echo -e "${CYAN}Load Installation Libraries${NC}")"
source "$SCRIPT_DIR/scripts/library.sh"
sh "$SCRIPT_DIR/scripts/set-timezone.sh"
sleep 2
_box "$(echo -e "${CYAN}Installation Libraries loaded${NC}")"
sleep 2
clear

# ─── Install Yay ────────────────────────────────────────
_box "$(echo -e "${CYAN}Install Yay${NC}")"

if pacman -Qs yay &>/dev/null; then
    echo -e "${CYAN}yay is installed.${NC}"
else
    echo -e "${CYAN}yay is not installed. Installing now...${NC}"
    _install_pacman "base-devel"
    if [ -d ~/Downloads/yay-git ]; then
        rm -rf ~/Downloads/yay-git
    fi
    if ! gum spin --spinner dot --title "Cloning yay..." -- git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git; then
        echo -e "${RED}Failed to clone yay.${NC}"
        exit 1
    fi
    (cd ~/Downloads/yay-git && makepkg -si --noconfirm) || die "makepkg failed for yay"
    pacman -Qs yay &>/dev/null || die "yay not found after installation"
    cd "$SCRIPT_DIR"
    clear
fi

_box "$(echo -e "${CYAN}Yay is Installed${NC}")"
sleep 2

if ! gum confirm --prompt.foreground=5 "Proceed with full installation?"; then
    echo -e "${MAGENTA}Installation cancelled.${NC}"
    exit 0
fi
clear

# ─── Graphics Card ──────────────────────────────────────
. "$SCRIPT_DIR/hypr/packages/graphics-card.sh"
sleep 2
clear

# ─── Core Apps ─────────────────────────────────────────
if gum confirm --prompt.foreground=5 "Install core applications?"; then
    figlet -f 3d "Core Apps"

    _box "$(echo -e "${CYAN}Installing required Packages${NC}")"

    for pkg in hyprland xfce4 filetools webtools printers network media terminaltools systemtools system hyprviz sddm-check sddmgrub matuwall; do
        echo -e "${CYAN}Installing $pkg...${NC}"
        . "$SCRIPT_DIR/hypr/packages/$pkg.sh"
        sleep 1
    done

    if [ -f "$SCRIPT_DIR/scripts/awww-wrapper.sh" ]; then
        . "$SCRIPT_DIR/scripts/awww-wrapper.sh"
    fi

    _box "$(echo -e "${CYAN}Installed required Packages${NC}")"
else
    echo -e "${MAGENTA}Core apps skipped.${NC}"
fi
clear

# ─── Install Pywal16 ────────────────────────────────────
_box "$(echo -e "${CYAN}Install Pywal16${NC}")"

if [ -f /usr/bin/wal ]; then
    echo -e "${CYAN}pywal16 already installed.${NC}"
else
    yay --noconfirm -S python-pywal16-git
fi

_box "$(echo -e "${CYAN}Pywal16 Installed${NC}")"
clear

# ─── Install Wallpapers ─────────────────────────────────
_box "$(echo -e "${CYAN}Install Wallpapers${NC}")"
. "$SCRIPT_DIR/hypr/packages/wallpapers.sh"
sleep 2
_box "$(echo -e "${CYAN}Wallpapers Installed${NC}")"
clear

# ─── Install Fonts ──────────────────────────────────────
_box "$(echo -e "${CYAN}Install Fonts${NC}")"
. "$SCRIPT_DIR/hypr/packages/fonts.sh"
sleep 2
_box "$(echo -e "${CYAN}Fonts Installed${NC}")"
clear

# ─── Install Icons Root ─────────────────────────────────
_box "$(echo -e "${CYAN}Install Icons Root${NC}")"
echo -e "${CYAN}Installing to root user${NC}"
if command -v wget &>/dev/null; then
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh
fi

_box "$(echo -e "${CYAN}Icons Installed${NC}")"
clear

# ─── Initiate Pywal16 ───────────────────────────────────
_box "$(echo -e "${CYAN}Initiating Pywal16${NC}")"

cp "$SCRIPT_DIR/Wallpapers/default.png" ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png

if [ "$DISTRO_ID" = "bslx" ]; then
    sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
fi

xdg-user-dirs-update --force 2>/dev/null || true
xdg-user-dirs-gtk-update --force 2>/dev/null || true

_box "$(echo -e "${CYAN}Pywal16 Initiated${NC}")"
sleep 2
clear

# ─── Hyprland Section ────────────────────────────────────
echo ""
figlet -f 3d "Hyprland"
echo -e "${CYAN}by hyprtk (Kori Tk) (2026)${NC}"
echo ""

skip_hyprland=false
if ! gum confirm --prompt.foreground=5 "Configure Hyprland and system services?"; then
    echo -e "${MAGENTA}Hyprland config skipped.${NC}"
    skip_hyprland=true
fi

if [ "$skip_hyprland" = false ]; then

# ─── Launch Thunar to generate xfconf ───────────────────
_box "$(echo -e "${CYAN}Launch Thunar to generate xfconf${NC}")"

if command -v thunar &>/dev/null; then
    thunar &
    sleep 3
    killall thunar 2>/dev/null || true
else
    echo -e "${YELLOW}thunar not found, skipping.${NC}"
fi
clear

# ─── Enable Bluetooth ────────────────────────────────────
_box "$(echo -e "${CYAN}Enabling Bluetooth${NC}")"
sudo systemctl start bluetooth 2>/dev/null || true
sudo systemctl enable bluetooth 2>/dev/null || true
clear

# ─── Enable Cockpit / OS-Release ────────────────────────
_box "$(echo -e "${CYAN}Enabling Cockpit${NC}")"

case "$DISTRO_ID" in
    archbang)
        sudo cp "$SCRIPT_DIR/os-release/os-release-archbang" /etc/os-release
        ;;
    cachyos)
        sudo cp "$SCRIPT_DIR/os-release/os-release-cachyos" /usr/lib/os-release 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/os-release/os-release-cachyos" /run/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/os-release/os-release-cachyos" /run/user/$UID/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        if [ -f "$SCRIPT_DIR/os-release/cachyos-branding" ]; then
            sudo cp "$SCRIPT_DIR/os-release/cachyos-branding" /usr/share/libalpm/scripts/
            sudo bash /usr/share/libalpm/scripts/cachyos-branding
        fi
        ;;
    endeavour|endeavouros)
        sudo cp "$SCRIPT_DIR/os-release/os-release-endeavouros" /usr/lib/os-release
        ;;
    garuda)
        sudo cp "$SCRIPT_DIR/os-release/os-release-garuda" /usr/lib/os-release
        ;;
    kiro)
        sudo cp "$SCRIPT_DIR/os-release/os-release-kiro" /usr/lib/os-release
        ;;
    manjaro)
        sudo cp "$SCRIPT_DIR/os-release/os-release-manjaro" /usr/lib/os-release
        ;;
    reborn|rebornos)
        sudo cp "$SCRIPT_DIR/os-release/os-release-rebornos" /usr/lib/os-release
        ;;
    archcraft)
        sudo cp "$SCRIPT_DIR/os-release/os-release-archcraft" /usr/lib/os-release
        ;;
    archman)
        sudo cp "$SCRIPT_DIR/os-release/os-release-archman" /usr/lib/os-release
        ;;
    bslx)
        sudo cp "$SCRIPT_DIR/os-release/os-release-bslx" /usr/lib/os-release
        ;;
    *)
        sudo cp "$SCRIPT_DIR/os-release/os-release-arch" /usr/lib/os-release
        ;;
esac

if [ -f "$SCRIPT_DIR/splash/splash-arch.bmp" ]; then
    sudo cp "$SCRIPT_DIR/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
fi
_rebuild_initramfs

if [ -f "$SCRIPT_DIR/User-Management/manage-users.desktop" ]; then
    sudo cp "$SCRIPT_DIR/User-Management/manage-users.desktop" /usr/share/applications/
fi
if command -v cockpit &>/dev/null; then
    sudo systemctl enable --now cockpit.socket 2>/dev/null || true
fi
clear

# ─── Enable Samba ─────────────────────────────────────────
_box "$(echo -e "${CYAN}Enabling Samba${NC}")"

if [ -f "$SCRIPT_DIR/smb/smb.conf" ]; then
    sudo cp "$SCRIPT_DIR/smb/smb.conf" /etc/samba/
fi
sudo systemctl enable smb nmb 2>/dev/null || true
sudo systemctl start smb nmb 2>/dev/null || true
sudo systemctl restart smb nmb 2>/dev/null || true
echo -e "${YELLOW}Please update the interfaces section of /etc/samba/smb.conf with your IP address${NC}"
sleep 3
clear

fi # end skip_hyprland

# ─── NVIDIA Info ─────────────────────────────────────────
_box "$(echo -e "${CYAN}Important Graphics Card Information${NC}")"
echo ""
echo -e "${WHITE}If you installed an NVIDIA Graphics Card please follow the instructions in the${NC}"
echo -e "${WHITE}nvidia.lua file located ~/hyprtk/hypr/nvidia.lua${NC}"
echo ""
sleep 5
clear

# ─── Dotfiles Install ────────────────────────────────────
figlet -f 3d "hyprtk"
echo -e "${CYAN}by hyprtk (Kori Tk) (2026)${NC}"
echo ""
echo -e "${WHITE}The script will remove existing directories from ~/.config/${NC}"
echo -e "${WHITE}Symbolic links will be created from ~/hyprtk into your ~/.config/${NC}"
echo ""
sleep 5
clear

skip_dotfiles=false
if ! gum confirm --prompt.foreground=5 "Install dotfiles?"; then
    echo -e "${MAGENTA}Dotfiles install skipped.${NC}"
    skip_dotfiles=true
fi

if [ "$skip_dotfiles" = false ]; then

# ─── Check .config ───────────────────────────────────────
_box "$(echo -e "${CYAN}Check .config directory exists${NC}")"
if [ -d ~/.config ]; then
    echo -e "${CYAN}.config folder already exists.${NC}"
else
    mkdir ~/.config
    echo -e "${CYAN}.config folder created.${NC}"
fi
sleep 3
clear

# ─── Create Symbolic Links ───────────────────────────────
_box "$(echo -e "${CYAN}Create Symbolic Links${NC}")"
echo ""
echo "-------------------------------------"
echo -e "${MAGENTA}Install general hyprtk${NC}"
echo "-------------------------------------"

_installSymLink alacritty ~/.config/alacritty ~/hyprtk/alacritty/
_installSymLink ranger ~/.config/ranger ~/hyprtk/ranger/
_installSymLink vim ~/.config/vim ~/hyprtk/vim/
_installSymLink nvim ~/.config/nvim ~/hyprtk/nvim/
_installSymLink starship ~/.config/starship.toml ~/hyprtk/starship/starship.toml
_installSymLink rofi ~/.config/rofi ~/hyprtk/rofi/
_installSymLink dunst ~/.config/dunst ~/hyprtk/dunst/
_installSymLink wal ~/.config/wal ~/hyprtk/wal/
_installSymLink btop ~/.config/btop ~/hyprtk/btop/
echo ""
clear

# ─── Re-Initiate Pywal16 ─────────────────────────────────
_box "$(echo -e "${CYAN}Re-Initiating Pywal16${NC}")"

if [ "$DISTRO_ID" = "archcraft" ]; then
    wal -i ~/.cache/current-wallpaper.png
else
    wal -i "$SCRIPT_DIR/Wallpapers/default.png"
fi

_box "$(echo -e "${CYAN}Pywal16 Initiated${NC}")"
clear

# ─── GTK ─────────────────────────────────────────────────
echo "-------------------------------------"
echo -e "${MAGENTA}Install GTK hyprtk${NC}"
echo "-------------------------------------"
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0/
_installSymLink themes ~/.local/share/themes ~/hyprtk/themes
_installSymLink icons ~/.local/share/icons ~/hyprtk/papirus-icons/icons
clear

# ─── XFCE ────────────────────────────────────────────────
echo "-------------------------------------"
echo -e "${MAGENTA}Install Xfce hyprtk${NC}"
echo "-------------------------------------"
_installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/xfce4
_installSymLink Thunar ~/.config/Thunar ~/hyprtk/Thunar
_installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/Mousepad
clear

# ─── Hyprland ────────────────────────────────────────────
echo "-------------------------------------"
echo -e "${MAGENTA}Install Hyprland hyprtk${NC}"
echo "-------------------------------------"

if [ "$DISTRO_ID" != "arch" ]; then
    if [ -d ~/.config/hypr ]; then
        mv ~/.config/hypr ~/.config/hypr-old
    fi
fi

_installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/
_installSymLink fastfetch ~/.config/fastfetch ~/hyprtk/fastfetch/
_installSymLink waybar ~/.config/waybar ~/hyprtk/waybar/
_installSymLink swaylock ~/.config/swaylock ~/hyprtk/swaylock/
_installSymLink swappy ~/.config/swappy ~/hyprtk/swappy/
_installSymLink hyprlogout ~/.config/hyprlogout ~/hyprtk/hyprlogout/
_installSymLink waypaper ~/.config/waypaper ~/hyprtk/waypaper/
_installSymLink zshrc ~/.config/zshrc ~/hyprtk/zshrc/
_installSymLink ohmyposh ~/.config/ohmyposh ~/hyprtk/ohmyposh/
_installSymLink matuwall ~/.config/matuwall ~/hyprtk/matuwall/
_installSymLink wob ~/.config/wob ~/hyprtk/wob/
mkdir -p ~/.local/bin
clear

# ─── ZSH ──────────────────────────────────────────────────
echo "-------------------------------------"
echo -e "${MAGENTA}Install ZSH${NC}"
echo "-------------------------------------"
sudo pacman -S zsh --noconfirm
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

echo "-------------------------------------"
echo -e "${MAGENTA}Install ZSH Plugins${NC}"
echo "-------------------------------------"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/fast-syntax-highlighting" 2>/dev/null || true

_box "$(echo -e "${CYAN}Update .zshrc${NC}")"
_installSymLink .zshrc ~/.zshrc ~/hyprtk/.zshrc

sudo chsh -s /bin/zsh 2>/dev/null || true
chsh -s /bin/zsh 2>/dev/null || true

_installSymLink standalone ~/.local/bin ~/hyprtk/standalone/
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/hyprtk/oh-my-zsh/oh-my-zsh.sh

[ -d "$HOME/dotfiles" ] && rm -Rf "$HOME/dotfiles"
clear

# ─── Root User Config ─────────────────────────────────────
echo "-------------------------------------"
echo -e "${MAGENTA}Setup Root User Config${NC}"
echo "-------------------------------------"
sudo cp -r "$SCRIPT_DIR/root" /
echo -e "${CYAN}Copying Config and Themes to ROOT User${NC}"
sleep 3

echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers >/dev/null 2>&1 || true
echo -e "${CYAN}Setup Password Feedback when entering SUDO password${NC}"
sleep 3
clear

# ─── Kiro-specific grub updater ───────────────────────────
if [ "$DISTRO_ID" = "kiro" ] && [ -f "$SCRIPT_DIR/scripts/update-grub.sh" ]; then
    sh "$SCRIPT_DIR/scripts/update-grub.sh"
fi

fi # end skip_dotfiles

# ─── Done ─────────────────────────────────────────────────
echo ""
_box "$(echo -e "${CYAN}Congratulations — Setup Complete${NC}")"
echo ""
echo -e "${WHITE}DONE!${NC}"
echo ""
echo -e "${WHITE}NEXT: Update the keyboard layout and screen resolution${NC}"
echo -e "${WHITE}in ~/hyprtk/hypr/hyprland.lua${NC}"
echo -e "${WHITE}Now reboot and Enjoy!${NC}"
echo ""
