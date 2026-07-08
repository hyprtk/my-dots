#!/bin/bash
#
# Unified Installer for Hyprland & XFCE (hyprtk)
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# All functionality merged into one self-contained script.
# Supports: arch, archbang, archcraft, archman, bluestar linux,
#           bslx, cachyos, endeavouros, garuda, kiro, manjaro, rebornos.
# -----------------------------------------------------

set -e  # exit on error

# ------------------- Error Handler -------------------
error_handler() {
    echo ""
    echo "ERROR: Installation failed at line $LINENO."
    echo "Please check the logs above for details."
    echo "If you need assistance, visit https://github.com/hyprtk"
    exit 1
}
trap error_handler ERR

# ------------------- Progress Bar -------------------
progress_bar() {
    local percent=$1
    local message=$2
    local width=50
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    printf "\rProgress: [%s%s] %3d%% - %s" \
        "$(printf '#%.0s' $(seq 1 $filled))" \
        "$(printf ' %.0s' $(seq 1 $empty))" \
        "$percent" "$message"
    if [ $percent -eq 100 ]; then
        echo ""
    fi
}

# ------------------- Professional Headers / Footers -------------------
print_header() {
    local msg="$1"
    echo ""
    echo "============================================================"
    echo "  $msg"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
}

print_footer() {
    local msg="$1"
    echo "------------------------------------------------------------"
    echo "  $msg - completed successfully"
    echo "------------------------------------------------------------"
    echo ""
}

# ------------------- Helper Functions -------------------
# Keep sudo credentials alive (with askpass support)
keep_sudo_alive() {
    # Try to set a graphical askpass if available
    if [ -z "$SUDO_ASKPASS" ]; then
        for askpass in /usr/lib/ssh/ssh-askpass /usr/bin/ksshaskpass /usr/bin/lxqt-sudo; do
            if [ -x "$askpass" ]; then
                export SUDO_ASKPASS="$askpass"
                break
            fi
        done
    fi
    # Use sudo -A if askpass is set, otherwise fallback to normal sudo
    if [ -n "$SUDO_ASKPASS" ]; then
        sudo -A -v
        while true; do sudo -A -n true; sleep 60; done 2>/dev/null &
    else
        sudo -v
        while true; do sudo -n true; sleep 60; done 2>/dev/null &
    fi
    SUDO_KEEP_ALIVE_PID=$!
    trap 'sudo -k; kill $SUDO_KEEP_ALIVE_PID 2>/dev/null' EXIT
}

# Rebuild initramfs (supports mkinitcpio and dracut)
rebuild_initramfs() {
    if command -v mkinitcpio &>/dev/null; then
        echo "Rebuilding initramfs with mkinitcpio..." >/dev/null
        sudo mkinitcpio -P >/dev/null
    elif command -v dracut &>/dev/null; then
        echo "Rebuilding initramfs with dracut..." >/dev/null
        sudo dracut --force >/dev/null
    else
        echo "No mkinitcpio or dracut found; skipping initramfs rebuild." >/dev/null
    fi
}

# Enhanced distribution detection
detect_distro() {
    if [ ! -f /etc/os-release ]; then
        echo "ERROR: /etc/os-release not found." >&2
        exit 1
    fi
    . /etc/os-release
    DISTRO_ID="${ID,,}"          # lowercase
    DISTRO_NAME="${NAME,,}"      # lowercase

    SUPPORTED=(
        "arch" "archbang" "archcraft" "archman"
        "bluestar linux" "bslx" "cachyos"
        "endeavouros" "garuda" "kiro"
        "manjaro" "rebornos"
    )

    for d in "${SUPPORTED[@]}"; do
        if [ "$DISTRO_ID" = "$d" ]; then
            echo "Detected supported distribution: $DISTRO_ID" >/dev/null
            return 0
        fi
        if [[ "$DISTRO_ID" == *"$d"* ]] || [[ "$DISTRO_NAME" == *"$d"* ]]; then
            echo "Detected supported distribution: $DISTRO_ID (via '$d')" >/dev/null
            return 0
        fi
    done

    echo "ERROR: Distribution '$DISTRO_ID' is not in the supported list." >&2
    echo "Supported: ${SUPPORTED[*]}" >&2
    exit 1
}

# ------------------- Conflict‑aware Pacman Installer -------------------
install_pacman_packages() {
    local pkgs=("$@")
    # First, attempt a dry run to detect conflicts
    local dry_output
    if ! dry_output=$(sudo pacman -S --dry-run --print-format='%n' "${pkgs[@]}" 2>&1); then
        # Check for conflict messages
        if echo "$dry_output" | grep -q "conflict\|conflicting"; then
            # Extract conflicting package names (this is heuristic)
            local conflict_pkgs
            conflict_pkgs=$(echo "$dry_output" | grep -oP "(?<=conflict with ).*?(?= )" | sort -u)
            if [ -n "$conflict_pkgs" ]; then
                echo "Conflicts detected: $conflict_pkgs. Removing conflicting packages..."
                # Force remove them (ignore dependencies)
                sudo pacman -Rdd --noconfirm $conflict_pkgs 2>/dev/null || true
                # Rebuild the database if needed
                sudo pacman -Syy --quiet >/dev/null
                # Retry installation
                sudo pacman -S --needed --noconfirm --quiet "${pkgs[@]}" >/dev/null
                return
            fi
        fi
        # If we can't resolve, let it fail
        sudo pacman -S --needed --noconfirm --quiet "${pkgs[@]}" >/dev/null
    else
        # No conflicts, proceed
        sudo pacman -S --needed --noconfirm --quiet "${pkgs[@]}" >/dev/null
    fi
}

# Check if package installed (pacman)
_isInstalledPacman() {
    package="$1"
    check="$(sudo pacman -Qs --color always "${package}" | grep "local" | grep "${package} " || true)"
    if [ -n "${check}" ]; then
        echo 0
        return
    fi
    echo 1
}

# Install via pacman (uses conflict handling)
_installPackagesPacman() {
    toInstall=()
    for pkg in "$@"; do
        if [[ $(_isInstalledPacman "${pkg}") == 0 ]]; then
            continue
        fi
        toInstall+=("${pkg}")
    done
    if [[ ${#toInstall[@]} -eq 0 ]]; then
        return
    fi
    install_pacman_packages "${toInstall[@]}"
}

# Dynamic AUR installer using chosen helper (global AUR_HELPER)
_installPackagesAUR() {
    toInstall=()
    for pkg in "$@"; do
        # Check if already installed using the chosen helper (or fallback)
        if [[ "$AUR_HELPER" == "yay" ]] || [[ "$AUR_HELPER" == "both" ]] && command -v yay &>/dev/null; then
            if yay -Qs "${pkg}" &>/dev/null; then
                continue
            fi
        elif [[ "$AUR_HELPER" == "paru" ]] || [[ "$AUR_HELPER" == "both" ]] && command -v paru &>/dev/null; then
            if paru -Qs "${pkg}" &>/dev/null; then
                continue
            fi
        else
            if command -v yay &>/dev/null; then
                if yay -Qs "${pkg}" &>/dev/null; then
                    continue
                fi
            elif command -v paru &>/dev/null; then
                if paru -Qs "${pkg}" &>/dev/null; then
                    continue
                fi
            else
                echo "ERROR: No AUR helper found." >&2
                exit 1
            fi
        fi
        toInstall+=("${pkg}")
    done
    if [[ ${#toInstall[@]} -eq 0 ]]; then
        return
    fi
    # Install using the chosen helper
    if [[ "$AUR_HELPER" == "yay" ]] || [[ "$AUR_HELPER" == "both" ]] && command -v yay &>/dev/null; then
        yay --noconfirm --quiet -S "${toInstall[@]}" >/dev/null
    elif [[ "$AUR_HELPER" == "paru" ]] || [[ "$AUR_HELPER" == "both" ]] && command -v paru &>/dev/null; then
        paru --noconfirm --quiet -S "${toInstall[@]}" >/dev/null
    elif command -v yay &>/dev/null; then
        yay --noconfirm --quiet -S "${toInstall[@]}" >/dev/null
    elif command -v paru &>/dev/null; then
        paru --noconfirm --quiet -S "${toInstall[@]}" >/dev/null
    else
        echo "ERROR: No AUR helper found to install packages." >&2
        exit 1
    fi
}

# Symbolic link installer – non‑interactive, silent
_installSymLink() {
    name="$1"
    symlink="$2"
    linksource="$3"
    linktarget="$4"

    if [ -L "${symlink}" ]; then
        rm "${symlink}"
    elif [ -e "${symlink}" ]; then
        rm -rf "${symlink}"
    fi
    ln -s "${linksource}" "${linktarget}"
    echo "Symlink ${linksource} -> ${linktarget} created."
}

# ------------------- Timezone -------------------
set_timezone() {
    echo "Setting timezone to Europe/London..." >/dev/null
    sudo timedatectl set-timezone Europe/London >/dev/null
    sudo timedatectl set-ntp true >/dev/null
    sudo timedatectl set-local-rtc 0 >/dev/null
}

# ------------------- Display Manager -------------------
switch_display_manager() {
    echo "Installing SDDM (if not present)..." >/dev/null
    _installPackagesPacman sddm

    echo "Disabling other display managers..." >/dev/null
    for dm in lightdm gdm lxdm slim kdm ly; do
        sudo systemctl disable "${dm}" 2>/dev/null || true
        sudo systemctl disable "${dm}-plymouth" 2>/dev/null || true
    done

    echo "Enabling SDDM..." >/dev/null
    sudo systemctl enable sddm >/dev/null
    sudo systemctl enable sddm --force >/dev/null
}

# ------------------- Backup hypr config -------------------
backup_hypr() {
    if [ -d ~/.config/hypr ]; then
        local backup_dir="$HOME/.config/hypr-$(date +%Y%m%d_%H%M%S)"
        mv ~/.config/hypr "$backup_dir"
        echo "Existing hypr config backed up to $backup_dir"
    fi
}

# ------------------- AUR Helper Installation -------------------
install_deps() {
    echo "Installing required dependencies..." >/dev/null
    _installPackagesPacman base-devel git
}

install_yay() {
    if command -v yay &> /dev/null; then
        echo "yay is already installed." >/dev/null
        return
    fi
    echo "Installing yay..." >/dev/null
    cd /tmp
    rm -rf yay
    git clone --quiet https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm >/dev/null
    cd ..
    rm -rf yay
    echo "yay installed successfully." >/dev/null
}

install_paru() {
    if command -v paru &> /dev/null; then
        echo "paru is already installed." >/dev/null
        return
    fi
    echo "Installing paru..." >/dev/null
    cd /tmp
    rm -rf paru
    git clone --quiet https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm >/dev/null
    cd ..
    rm -rf paru
    echo "paru installed successfully." >/dev/null
}

# ------------------- Start of Main Script -------------------
keep_sudo_alive
detect_distro
clear

print_header "Welcome to the Hyprland & XFCE installer"
echo ""
echo "I have chosen as my preference to install both, if you choose No on either"
echo "Environment the installer will fail and close. I chose it this way so if"
echo "1 Environment has problems i still have the other to boot too, enjoy."
echo ""
echo "You will now be asked to enter your Root password to proceed."
echo ""
sleep 2

print_header "Installation by hyprtk (Kori Tk) (2026)"
sleep 2
clear

progress_bar 0 "Starting installation"

# ---------- AUR Helper Selection Menu ----------
print_header "Arch AUR Helper Selection"
echo "1) Install yay"
echo "2) Install paru"
echo "3) Install BOTH yay and paru"
echo "4) Exit"
read -rp "Select an option [1-4]: " choice

AUR_HELPER=""

case $choice in
    1)
        install_deps
        install_yay
        AUR_HELPER="yay"
        ;;
    2)
        install_deps
        install_paru
        AUR_HELPER="paru"
        ;;
    3)
        install_deps
        install_yay
        install_paru
        AUR_HELPER="both"
        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac
print_footer "AUR helper configured"

progress_bar 5 "AUR helper configured"

# ---------- Remove leftover packages (distro‑specific) ----------
print_header "Removing leftover Packages"
sleep 2

# Common removals (plasma, kde)
sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true

# Distro‑specific removals
case $DISTRO_ID in
    archbang)
        sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
        ;;
    bslx)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
        ;;
    kiro)
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
        _installPackagesAUR sddm-git fastfetch-git 2>/dev/null || true
        ;;
    *) ;;
esac

echo ""
clear
print_footer "Leftover removal completed"
progress_bar 7 "Removing leftovers"

# ---------- Timezone ----------
print_header "Setting Timezone"
set_timezone
echo ""
sleep 1
clear
print_footer "Timezone set to Europe/London"
progress_bar 10 "Timezone set"

# ---------- Graphics card detection ----------
print_header "Graphics Card Selection"
echo "1) Intel"
echo "2) AMD"
echo "3) Nvidia"
echo "4) Virtualization (QEMU/virt & VMware)"
echo "Defaults to AMD if you choose something else"
echo ""
read -r GRAPHICSCARD

case $GRAPHICSCARD in
1)
    _installPackagesPacman xf86-video-intel mesa vulkan-intel
    ;;
2)
    _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
    rebuild_initramfs
    ;;
3)
    sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null

    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf >/dev/null

    _installPackagesPacman nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
    _installPackagesAUR libva-nvidia-driver-git
    rebuild_initramfs
    ;;
4)
    echo "Installing virtualization guest drivers (QEMU/virt & VMware)..." >/dev/null
    _installPackagesPacman qemu-guest-agent spice-vdagent xf86-video-qxl mesa
    _installPackagesAUR xf86-video-vmware open-vm-tools
    sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
    sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
    sudo systemctl enable --now vmtoolsd 2>/dev/null || true
    ;;
*)
    _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
    rebuild_initramfs
    ;;
esac
echo ""
print_footer "Graphics card drivers installed"
progress_bar 15 "Graphics card drivers installed"

# ---------- Prompt core apps (removed interactive prompt; now automatic) ----------
print_header "Installing Core Applications"
echo "Proceeding with core application installation..."
sleep 2
clear

# ------------------- HYPRLAND -------------------
print_header "Installing Hyprland and related packages"
_installPackagesPacman \
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

_installPackagesAUR \
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

echo ""
sleep 1
print_footer "Hyprland installed"
progress_bar 25 "Hyprland installed"

# ------------------- XFCE4 -------------------
print_header "Installing XFCE4 and extras"
_installPackagesPacman xfce4 xfce4-goodies parole
_installPackagesAUR tumbler-extra-thumbnailers
echo ""
sleep 1
print_footer "XFCE4 installed"
progress_bar 30 "XFCE4 installed"

# ------------------- FILE TOOLS -------------------
print_header "Installing File Tools"
_installPackagesPacman thunar mousepad
_installPackagesAUR thunar-shares-plugin
echo ""
sleep 1
print_footer "File tools installed"
progress_bar 33 "File tools installed"

# ------------------- WEB TOOLS -------------------
print_header "Installing Web Tools"
_installPackagesPacman chromium
_installPackagesAUR brave-bin github-desktop-bin
echo ""
sleep 1
print_footer "Web tools installed"
progress_bar 36 "Web tools installed"

# ------------------- PRINTERS -------------------
print_header "Installing Printer Packages"
_installPackagesAUR cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate
echo ""
sleep 1
print_footer "Printer packages installed"
progress_bar 39 "Printer packages installed"

# ------------------- NETWORK -------------------
print_header "Installing Network and Filesystem Packages"
_installPackagesPacman \
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
echo ""
sleep 1
print_footer "Network packages installed"
progress_bar 42 "Network packages installed"

# ------------------- MEDIA -------------------
print_header "Installing Media Packages"
_installPackagesPacman xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg
_installPackagesAUR hyprquickframe-git
echo ""
sleep 1
print_footer "Media packages installed"
progress_bar 45 "Media packages installed"

# ------------------- TERMINAL TOOLS (figlet removed) -------------------
print_header "Installing Terminal Tools"
_installPackagesPacman eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim
_installPackagesAUR fastfetch
echo ""
sleep 1
print_footer "Terminal tools installed"
progress_bar 48 "Terminal tools installed"

# ------------------- SYSTEM TOOLS -------------------
print_header "Installing System Tools"
_installPackagesPacman \
    timeshift \
    file-roller \
    gparted \
    xfce4-power-manager \
    rofi \
    dunst \
    cockpit
_installPackagesAUR gnome-disk-utility
echo ""
sleep 1
print_footer "System tools installed"
progress_bar 51 "System tools installed"

# ------------------- SYSTEM -------------------
print_header "Installing System Packages"
_installPackagesPacman \
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
sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm --quiet >/dev/null

YAY_PKGS=(
    bibata-cursor-theme
    trizen
    sublime-text-4
    sddm-theme-sugar-candy-git
    pacseek
    tumbler-extra-thumbnailers
)
if [[ "$DISTRO_ID" != "rebornos" ]]; then
    YAY_PKGS+=(pamac-all libpamac-full pamac-cli)
fi
_installPackagesAUR "${YAY_PKGS[@]}"

wget -qO- https://git.io/papirus-folders-install | env PREFIX="$HOME/.local" sh >/dev/null
echo ""
sleep 1
print_footer "System packages installed"
progress_bar 55 "System packages installed"

# ------------------- HYPRVIZ -------------------
print_header "Installing HyprViz (Hyprland Configuration Tool)"
mkdir -p "$HOME/Downloads/yay-git/src"
cd "$HOME/Downloads/yay-git/src"
if [ -d "hyprviz-bin" ]; then
    cd hyprviz-bin && git pull --quiet
else
    git clone --quiet https://aur.archlinux.org/hyprviz-bin.git && cd hyprviz-bin
fi
makepkg -si --noconfirm >/dev/null
cd -
echo ""
sleep 1
print_footer "HyprViz installed"
progress_bar 58 "HyprViz installed"

# ------------------- MATUWALL (fresh install, remove existing) -------------------
print_header "Installing Matuwall"
REPO_DIR="$HOME/.local/share/Matuwall"
if [ -d "$REPO_DIR" ]; then
    rm -rf "$REPO_DIR"
fi
git clone --quiet https://github.com/naurissteins/Matuwall.git "$REPO_DIR"
cd "$REPO_DIR"
python3 -m venv --system-site-packages .venv >/dev/null
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install . >/dev/null
mkdir -p "$HOME/.local/bin"
ln -sf "$(pwd)/.venv/bin/matuwall" "$HOME/.local/bin/matuwall"
cd -
echo ""
sleep 1
print_footer "Matuwall installed"
progress_bar 61 "Matuwall installed"

# ------------------- SDDM CHECK -------------------
print_header "Installing SDDM"
_installPackagesPacman sddm
for dm in lightdm gdm lxdm slim kdm ly; do
    sudo systemctl disable "$dm" 2>/dev/null || true
    sudo systemctl disable "${dm}-plymouth" 2>/dev/null || true
done
sudo systemctl enable sddm >/dev/null
sudo systemctl enable sddm --force >/dev/null
CONFIG_DIR="/etc/sddm.conf.d"
CONFIG_FILE="$HOME/hyprtk/sddm/sddm.conf"
if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
fi
if [ -f "$CONFIG_FILE" ]; then
    sudo cp "$CONFIG_FILE" "$CONFIG_DIR/"
else
    echo "WARNING: $CONFIG_FILE not found."
fi
echo ""
sleep 1
print_footer "SDDM configured"
progress_bar 64 "SDDM configured"

# ------------------- Display Manager switch -------------------
switch_display_manager

# ------------------- SDDM & GRUB THEMING -------------------
print_header "Starting system theming setup"
SOURCE_SDDM_CONF="$HOME/hyprtk/sddm/sddm.conf"
SOURCE_THEME_CONF="$HOME/hyprtk/sddm/theme.conf"
SOURCE_WALLPAPER="$HOME/hyprtk/default.png"
SDDM_THEME_DIR="/usr/share/sddm/themes/Sugar-Candy"
if [ -f "$SOURCE_SDDM_CONF" ] && [ -f "$SOURCE_THEME_CONF" ] && [ -f "$SOURCE_WALLPAPER" ] && [ -d "$SDDM_THEME_DIR" ]; then
    sudo cp "$SOURCE_SDDM_CONF" /etc/sddm.conf.d/
    cp "$SOURCE_WALLPAPER" ~/.cache/current-wallpaper.png
    sudo cp ~/.cache/current-wallpaper.png "$SDDM_THEME_DIR/Backgrounds/"
    sudo cp "$SOURCE_THEME_CONF" "$SDDM_THEME_DIR/"
    sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png

    sudo rm -rf /usr/share/grub/themes/*
    sudo rm -rf /boot/grub/themes/*
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo tee -a /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
    sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
    echo "Skipping theming: required files or directories missing."
fi
echo ""
sleep 1
print_footer "Theming applied"
progress_bar 67 "Theming applied"

# ------------------- WALLPAPERS -------------------
print_header "Installing Wallpapers"
while true; do
    read -p "Do you want to clone the wallpapers? If not, the script will install 3 default wallpapers to ~/Pictures/Wallpapers/ (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ ! -d ~/Pictures/Wallpapers/ ]; then
                git clone --quiet https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
            else
                echo "Wallpaper folder already exists."
            fi
            echo "Wallpapers installed."
            break
            ;;
        [Nn]* )
            if [ ! -d ~/Pictures/Wallpapers/ ]; then
                mkdir -p ~/Pictures/Wallpapers
            fi
            cp ~/hyprtk/Wallpapers/* ~/Pictures/Wallpapers 2>/dev/null || true
            echo "Default wallpapers installed."
            break
            ;;
        * ) echo "Please answer yes or no." ;;
    esac
done
echo ""
sleep 1
print_footer "Wallpapers installed"
progress_bar 70 "Wallpapers installed"

# ------------------- FONTS -------------------
print_header "Installing Fonts"
REPO_URL="https://github.com/hyprtk/fonts.git"
USER_FONT_DIR="$HOME/.local/share/fonts"
while true; do
    read -p "Install fonts to user directory (Y) or system-wide (N)? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ -d "$USER_FONT_DIR" ]; then
                read -p "Overwrite with fresh clone? (y/n): " overwrite
                if [[ $overwrite =~ [Yy] ]]; then
                    rm -rf "$USER_FONT_DIR"
                    git clone --quiet "$REPO_URL" "$USER_FONT_DIR"
                else
                    echo "Keeping existing fonts."
                fi
            else
                mkdir -p "$USER_FONT_DIR"
                git clone --quiet "$REPO_URL" "$USER_FONT_DIR"
            fi
            echo "User fonts installed."
            break
            ;;
        [Nn]* )
            TMP_DIR=$(mktemp -d)
            git clone --quiet "$REPO_URL" "$TMP_DIR"
            sudo cp -r "$TMP_DIR"/* /usr/share/fonts/
            sudo fc-cache -fv >/dev/null
            rm -rf "$TMP_DIR"
            echo "System fonts installed."
            break
            ;;
        * ) echo "Please answer yes (Y/y) or no (N/n)." ;;
    esac
done
echo ""
sleep 1
print_footer "Fonts installed"
progress_bar 73 "Fonts installed"

# ------------------- PYTHON PYwal16 -------------------
print_header "Installing Pywal16"
if [ ! -f /usr/bin/wal ]; then
    _installPackagesAUR python-pywal16-git
fi
echo ""
sleep 1
print_footer "Pywal16 installed"
progress_bar 76 "Pywal16 installed"

# ------------------- WALLPAPER INIT -------------------
print_header "Initiating Pywal16"
wal -i ~/hyprtk/Wallpapers/default.png >/dev/null
cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force   

case $DISTRO_ID in
    archbang|bslx)
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
        ;;
esac

xdg-user-dirs-update --force 2>/dev/null || true
if command -v xdg-user-dirs-gtk-update &>/dev/null; then
    xdg-user-dirs-gtk-update --force 2>/dev/null || true
fi
echo "default wallpaper copied."
sleep 2
clear
print_footer "Wallpaper initialized"
progress_bar 78 "Wallpaper initialized"

# ------------------- Hyprland section (no confirmation) -------------------
print_header "Hyprland Configuration by hyprtk (Kori Tk) (2026)"
echo "Proceeding with Hyprland configuration..."
echo ""

# ------------------- Generate xfconf via Thunar -------------------
echo "-> Launching Thunar to populate xfconf"
thunar &
sleep 3
killall thunar 2>/dev/null || true
echo ""
clear
print_footer "Xfconf generated"
progress_bar 80 "Xfconf generated"

# ------------------- Enable Services -------------------
print_header "Enabling Bluetooth"
sudo systemctl start bluetooth >/dev/null
sudo systemctl enable bluetooth >/dev/null
echo ""
print_footer "Bluetooth enabled"
progress_bar 82 "Bluetooth enabled"

print_header "Enabling Cockpit"
case $DISTRO_ID in
    archbang)
        sudo cp ~/hyprtk/os-release/os-release /etc/
        ;;
    cachyos)
        sudo cp ~/hyprtk/os-release/os-release /usr/lib/
        sudo cp ~/hyprtk/os-release/os-release /run/systemd/propagate/.os-release-stage/
        sudo cp ~/hyprtk/os-release/os-release /run/user/$UID/systemd/propagate/.os-release-stage/ 2>/dev/null || true
        sudo cp ~/hyprtk/os-release/cachyos-branding /usr/share/libalpm/scripts/ 2>/dev/null || true
        sudo bash /usr/share/libalpm/scripts/cachyos-branding 2>/dev/null || true
        ;;
    arch)
        sudo cp ~/hyprtk/os-release/os-release /usr/lib/
        sudo cp ~/hyprtk/splash/splash-arch.bmp /usr/share/systemd/bootctl/ 2>/dev/null || true
        rebuild_initramfs
        ;;
    *)
        sudo cp ~/hyprtk/os-release/os-release /usr/lib/
        ;;
esac
sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
sudo systemctl enable --now cockpit.socket >/dev/null
sudo systemctl start cockpit.socket >/dev/null
echo ""
print_footer "Cockpit enabled"
progress_bar 85 "Cockpit enabled"

print_header "Enabling Samba"
sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
sudo systemctl enable smb nmb >/dev/null
sudo systemctl start smb nmb >/dev/null
sudo systemctl restart smb nmb >/dev/null
echo "Please update the interfaces section of /etc/samba/smb.conf with your IP address"
sleep 3
clear
print_footer "Samba enabled"
progress_bar 87 "Samba enabled"

echo "=== Important Graphic Card Information ==="
echo ""
echo "If you installed an NVIDIA Graphics Card please follow the instructions in the"
echo "nvidia.conf file located ~/hyprtk/hypr/conf/nvidia.conf"
echo ""
sleep 5
clear

# ------------------- Dotfiles installation (no confirmation) -------------------
print_header "hyprtk Dotfiles Installation by hyprtk (Kori Tk) (2026)"
echo "The script will now create symbolic links from ~/hyprtk into ~/.config/"
echo "Existing directories/files will be removed automatically."
echo ""
sleep 5
clear

# ------------------- Backup hypr config -------------------
backup_hypr
print_footer "Hypr config backed up"
progress_bar 90 "Hypr config backed up"

# ------------------- Ensure .config exists -------------------
if [ ! -d ~/.config ]; then
    mkdir ~/.config
fi
echo ""
sleep 3
clear

# ------------------- Create Symbolic Links -------------------
print_header "Creating Symbolic Links"
echo "-> Installing general hyprtk"
_installSymLink alacritty ~/.config/alacritty ~/hyprtk/alacritty/ ~/.config
_installSymLink ranger ~/.config/ranger ~/hyprtk/ranger/ ~/.config
_installSymLink vim ~/.config/vim ~/hyprtk/vim/ ~/.config
_installSymLink nvim ~/.config/nvim ~/hyprtk/nvim/ ~/.config
_installSymLink starship ~/.config/starship.toml ~/hyprtk/starship/starship.toml ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi ~/hyprtk/rofi/ ~/.config
_installSymLink dunst ~/.config/dunst ~/hyprtk/dunst/ ~/.config
_installSymLink wal ~/.config/wal ~/hyprtk/wal/ ~/.config
_installSymLink btop ~/.config/btop ~/hyprtk/btop/ ~/.config
echo ""
clear
print_footer "General symlinks created"
progress_bar 92 "General symlinks created"

# Re-initiate pywal
wal -i ~/hyprtk/Wallpapers/default.png >/dev/null
echo "Pywal16 templates initiated!"
clear
sleep 2

# GTK symlinks
echo "-> Installing GTK hyprtk"
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0/ ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0/ ~/.config/
_installSymLink themes ~/.local/share/themes ~/hyprtk/themes ~/.local/share/
_installSymLink icons ~/.local/share/icons ~/hyprtk/papirus-icons/icons ~/.local/share/
echo ""
clear
print_footer "GTK symlinks created"
progress_bar 94 "GTK symlinks created"

# Xfce symlinks
echo "-> Installing Xfce hyprtk"
_installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/xfce4 ~/.config/
_installSymLink Thunar ~/.config/Thunar ~/hyprtk/Thunar ~/.config/
_installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/Mousepad ~/.config/
echo ""
clear
print_footer "XFCE symlinks created"
progress_bar 95 "XFCE symlinks created"

# Hyprland symlinks
echo "-> Installing Hyprland hyprtk"
_installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/ ~/.config
_installSymLink fastfetch ~/.config/fastfetch ~/hyprtk/fastfetch/ ~/.config
_installSymLink waybar ~/.config/waybar ~/hyprtk/waybar/ ~/.config
_installSymLink swaylock ~/.config/swaylock ~/hyprtk/swaylock/ ~/.config
_installSymLink swappy ~/.config/swappy ~/hyprtk/swappy/ ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout ~/hyprtk/hyprlogout/ ~/.config
_installSymLink waypaper ~/.config/waypaper ~/hyprtk/waypaper/ ~/.config
_installSymLink zshrc ~/.config/zshrc ~/hyprtk/zshrc/ ~/.config
_installSymLink ohmyposh ~/.config/ohmyposh ~/hyprtk/ohmyposh/ ~/.config
_installSymLink matuwall ~/.config/matuwall ~/hyprtk/matuwall/ ~/.config
_installSymLink wob ~/.config/wob ~/hyprtk/wob/ ~/.config
mkdir -p ~/.local/bin
echo ""
clear
print_footer "Hyprland symlinks created"
progress_bar 97 "Hyprland symlinks created"

# ------------------- ZSH installation (fresh) -------------------
print_header "Installing ZSH"
rm -rf ~/.oh-my-zsh
sudo pacman -S zsh --noconfirm --quiet >/dev/null
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null
echo "Installing ZSH Plugins"
git clone --quiet https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone --quiet https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
_installSymLink .zshrc ~/.zshrc ~/hyprtk/.zshrc ~/.zshrc
sudo chsh -s /bin/zsh
chsh -s /bin/zsh
_installSymLink standalone ~/.local/bin ~/hyprtk/standalone/ ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/hyprtk/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh
rm -Rf $HOME/dotfiles 2>/dev/null || true
clear
print_footer "ZSH installed"
progress_bar 99 "ZSH installed"

# ------------------- Root User Config -------------------
print_header "Setup Root User Config"
sudo cp -r ~/hyprtk/root /
echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers >/dev/null
echo ""
sleep 3
clear
print_footer "Root config applied"
progress_bar 100 "Root config applied"

# ------------------- Completion -------------------
print_header "Congratulations! Setup Complete"
echo ""
echo "DONE!"
echo ""
echo "NEXT: Update the keyboard layout and screen resolution:"
echo "  keyboard layout ~/hyprtk/hypr/input.lua"
echo "  screen resolution ~/hyprtk/hypr/monitors.lua"
echo ""
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""
print_footer "Installation finished successfully"