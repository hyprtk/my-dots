#!/bin/bash
#
# Unified Installer for Hyprland & XFCE (hyprtk)
# by hyprtk (Kori Tk) (2026) – Merged & Optimised
# -----------------------------------------------------

set -euo pipefail  # strict error handling

# ------------------- Askpass / Sudo Caching -------------------
# Cache sudo credentials at start to avoid repeated prompts
sudo -v
# Keep sudo alive during script
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ------------------- Detect Distribution -------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID,,}"  # lowercase
else
    DISTRO_ID="unknown"
fi

# ------------------- Helper Functions (library.sh & extended) -------------------

_isInstalledPacman() {
    pacman -Q "$1" &>/dev/null && echo 0 || echo 1
}

_isInstalledAUR() {
    # works with both yay and paru (they share same syntax for -Q)
    if command -v yay &>/dev/null; then
        yay -Q "$1" &>/dev/null && echo 0 || echo 1
    elif command -v paru &>/dev/null; then
        paru -Q "$1" &>/dev/null && echo 0 || echo 1
    else
        echo 1
    fi
}

_packageExistsPacman() {
    pacman -Si "$1" &>/dev/null
}

_packageExistsAUR() {
    # Use the selected helper or fallback to yay/paru
    local helper="${AUR_HELPER:-yay}"
    if [[ "$helper" == "both" ]]; then helper="yay"; fi
    $helper -Si "$1" &>/dev/null
}

# ---------- Conflict detection (basic) ----------
check_package_conflicts() {
    local conflicts=()
    for pkg in "$@"; do
        # Check if package exists in repos
        if _packageExistsPacman "$pkg"; then
            # Get conflict list from pacman
            local pkg_conflicts
            pkg_conflicts=$(pacman -Si "$pkg" 2>/dev/null | grep -i "^Conflicts With" | sed 's/Conflicts With\s*:\s*//' | tr ' ' '\n' | grep -v '^$')
            for conflict in $pkg_conflicts; do
                if pacman -Q "$conflict" &>/dev/null; then
                    conflicts+=("$pkg conflicts with already installed $conflict")
                fi
            done
        fi
    done
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "WARNING: Potential conflicts detected:"
        printf '  %s\n' "${conflicts[@]}"
        echo "Installation will continue, but you may need to resolve them manually."
    fi
}

# ---------- Install pacman packages ----------
_installPackagesPacman() {
    local failed=()
    # Pre-check conflicts for all packages
    check_package_conflicts "$@"
    for pkg in "$@"; do
        if [[ $(_isInstalledPacman "$pkg") == 0 ]]; then
            echo "[PACMAN] $pkg already installed."
            continue
        fi
        if ! _packageExistsPacman "$pkg"; then
            echo "[PACMAN] $pkg not found in repositories – skipping."
            continue
        fi
        echo "Installing $pkg ..."
        if sudo pacman --noconfirm --needed -S "$pkg"; then
            echo "$pkg installed successfully."
        else
            echo "ERROR: Failed to install $pkg (conflict or other issue). Skipping."
            failed+=("$pkg")
        fi
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "The following pacman packages could NOT be installed: ${failed[*]}"
    fi
}

# ---------- Install AUR packages (supports yay, paru, or both) ----------
_installPackagesAUR() {
    local failed=()
    # Pre-check conflicts (AUR packages may not be in pacman, but we can check if they conflict with installed)
    # For simplicity, we skip conflict checks for AUR here (could be extended)
    local helper_cmd
    for pkg in "$@"; do
        if [[ $(_isInstalledAUR "$pkg") == 0 ]]; then
            echo "[AUR] $pkg already installed."
            continue
        fi
        # Determine which helper to use
        if [[ "$AUR_HELPER" == "both" ]]; then
            helper_cmd="yay"   # default to yay
        else
            helper_cmd="$AUR_HELPER"
        fi
        if ! _packageExistsAUR "$pkg"; then
            echo "[AUR] $pkg not found in AUR – skipping."
            continue
        fi
        echo "Installing $pkg from AUR using $helper_cmd ..."
        if $helper_cmd --noconfirm --needed -S "$pkg"; then
            echo "$pkg installed successfully."
        else
            echo "ERROR: Failed to install $pkg. Skipping."
            failed+=("$pkg")
        fi
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "The following AUR packages could NOT be installed: ${failed[*]}"
    fi
}

# Force symlink installation (no prompts)
_installSymLink() {
    local name="$1"
    local symlink="$2"
    local linksource="$3"
    local linktarget="$4"
    
    if [ -L "${symlink}" ] || [ -e "${symlink}" ]; then
        rm -rf "${symlink}"
    fi
    ln -s "${linksource}" "${linktarget}"
    echo "Symlink ${linksource} -> ${linktarget} created."
}

# Regenerate initramfs (supports both mkinitcpio and dracut)
_update_initramfs() {
    if command -v dracut &>/dev/null; then
        echo "Regenerating initramfs with dracut..."
        sudo dracut --regenerate-all --force
    elif command -v mkinitcpio &>/dev/null; then
        echo "Regenerating initramfs with mkinitcpio..."
        sudo mkinitcpio -P
    else
        echo "No initramfs generator found (mkinitcpio or dracut). Skipping."
    fi
}

# Backup existing hypr config
backup_hypr() {
    if [ -d ~/.config/hypr ]; then
        local backup_dir="$HOME/.config/hypr-$(date +%Y%m%d_%H%M%S)"
        mv ~/.config/hypr "$backup_dir"
        echo "Existing hypr config backed up to $backup_dir"
    fi
}

# ------------------- Professional Headers / Footers -------------------
print_step_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
}

print_step_footer() {
    echo ""
    echo "───────────────────────────────────────────────────────────────────"
    echo "  ✓ $1 completed"
    echo "───────────────────────────────────────────────────────────────────"
    echo ""
}

# ------------------- AUR Helper Selection -------------------
select_aur_helper() {
    print_step_header "Select AUR Helper"
    echo "Select the AUR helper to use for installing AUR packages:"
    echo "  1) yay (default)"
    echo "  2) paru"
    echo "  3) Both (install both; yay will be used for installations)"
    read -rp "Enter choice [1-3]: " choice
    case "$choice" in
        2) AUR_HELPER="paru" ;;
        3) AUR_HELPER="both" ;;
        *) AUR_HELPER="yay" ;;
    esac
    echo "Selected AUR helper: $AUR_HELPER"
    print_step_footer "AUR Helper Selection"
}

# ------------------- Package Lists (from test-app-installer) -------------------

PACMAN_SYSTEM_PKGS=(
    awesome-terminal-fonts
    blueman
    brightnessctl
    cockpit
    curl
    dunst
    exa
    file-roller
    font-manager
    fzf
    gnome-keyring
    gparted
    gtk4-layer-shell
    hyprland
    hyprpicker
    imagemagick
    jq
    libadwaita
    mission-center
    nano
    neovim
    network-manager-applet
    networkmanager
    nwg-look
    os-prober
    pacman-contrib
    pamixer
    pavucontrol
    pcp
    pcp-gui
    playerctl
    polkit-gnome
    python
    python-click
    python-gobject
    python-pip
    python-psutil
    python-rich
    python-virtualenv
    rofi
    sddm
    swayidle
    swappy
    timeshift
    ttf-fira-code
    ttf-fira-sans
    ttf-firacode-nerd
    ttf-font-awesome
    tumbler
    vlc
    wf-recorder
    xclip
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
    xdg-user-dirs
    xdg-user-dirs-gtk
    xfce4-power-manager
    xorg-xhost
)

AUR_SYSTEM_PKGS=(
    bibata-cursor-theme
    fastfetch
    gnome-disk-utility
    libpamac-full
    pacseek
    pamac-all
    pamac-cli
    sddm-theme-sugar-candy-git
    sublime-text-4
    thunar-shares-plugin
    trizen
    tumbler-extra-thumbnailers
)

PACMAN_MEDIA_PKGS=(
    ffmpeg
    mpv
    pavucontrol
    tumbler
    vlc
    wf-recorder
    xclip
)

AUR_MEDIA_PKGS=(
    hyprquickframe-git
)

PACMAN_NETWORK_PKGS=(
    curl
    freerdp
    git
    gvfs
    gvfs-afc
    gvfs-dnssd
    gvfs-goa
    gvfs-gphoto2
    gvfs-mtp
    gvfs-nfs
    gvfs-onedrive
    gvfs-smb
    gvfs-wsdd
    network-manager-applet
    networkmanager
    ntfs-3g
    samba
)

AUR_PRINTER_PKGS=(
    colord
    cups
    cups-browsed
    cups-filters
    cups-pdf
    ipp-usb
    libusb
    logrotate
    nss-mdns
    system-config-printer
    xdg-utils
)

PACMAN_HYPRLAND_PKGS=(
    bc
    brightnessctl
    cliphist
    curl
    gtk-layer-shell
    gtk4
    hyprland
    imagemagick
    jq
    libadwaita
    mission-center
    nwg-look
    playerctl
    python
    python-gobject
    python-pip
    python-virtualenv
    swayidle
    swappy
    wob
    xdg-desktop-portal-wlr
    xorg-xhost
)

AUR_HYPRLAND_PKGS=(
    7zip
    awww
    gvfs-afc
    gvfs-goa
    gvfs-gphoto2
    gvfs-mtp
    gvfs-nfs
    gvfs-smb
    swaylock-effects
    unrar
    unzip
    waybar-git
)

PACMAN_TERMINAL_PKGS=(
    alacritty
    btop
    eza
    kitty
    micro
    nano
    neovim
    ranger
    starship
    xfce4-terminal
)

AUR_TERMINAL_PKGS=(
    fastfetch
)

PACMAN_SYS_TOOLS=(
    cockpit
    dunst
    file-roller
    gparted
    rofi
    timeshift
    xfce4-power-manager
)

AUR_SYS_TOOLS=(
    gnome-disk-utility
)

PACMAN_WEB_PKGS=(
    chromium
)

AUR_WEB_PKGS=(
    brave-bin
    github-desktop-bin
)

AUR_3D_PKGS=(
    bambustudio-bin
    orca-slicer-bin
)

PACMAN_XFCE4_PKGS=(
    parole
    xfce4
    xfce4-goodies
)

AUR_XFCE4_PKGS=(
    tumbler-extra-thumbnailers
)

# ------------------- Installation Functions (by category) -------------------

install_system() {
    print_step_header "Installing System Packages"
    _installPackagesPacman "${PACMAN_SYSTEM_PKGS[@]}"
    _installPackagesAUR "${AUR_SYSTEM_PKGS[@]}"
    sudo pacman -S $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null) --noconfirm 2>/dev/null || true
    echo "Papirus Folders Install"
    wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
    print_step_footer "System Packages"
}

install_media() {
    print_step_header "Installing Media Packages"
    _installPackagesPacman "${PACMAN_MEDIA_PKGS[@]}"
    _installPackagesAUR "${AUR_MEDIA_PKGS[@]}"
    print_step_footer "Media Packages"
}

install_network() {
    print_step_header "Installing Network Packages"
    _installPackagesPacman "${PACMAN_NETWORK_PKGS[@]}"
    print_step_footer "Network Packages"
}

install_printers() {
    print_step_header "Installing Printer Packages"
    _installPackagesAUR "${AUR_PRINTER_PKGS[@]}"
    print_step_footer "Printer Packages"
}

install_hyprland() {
    print_step_header "Installing Hyprland Packages"
    _installPackagesPacman "${PACMAN_HYPRLAND_PKGS[@]}"
    _installPackagesAUR "${AUR_HYPRLAND_PKGS[@]}"
    print_step_footer "Hyprland Packages"
}

install_terminal_tools() {
    print_step_header "Installing Terminal Tools"
    _installPackagesPacman "${PACMAN_TERMINAL_PKGS[@]}"
    _installPackagesAUR "${AUR_TERMINAL_PKGS[@]}"
    print_step_footer "Terminal Tools"
}

install_system_tools() {
    print_step_header "Installing System Tools"
    _installPackagesPacman "${PACMAN_SYS_TOOLS[@]}"
    _installPackagesAUR "${AUR_SYS_TOOLS[@]}"
    print_step_footer "System Tools"
}

install_web_tools() {
    print_step_header "Installing Web Tools"
    _installPackagesPacman "${PACMAN_WEB_PKGS[@]}"
    _installPackagesAUR "${AUR_WEB_PKGS[@]}"
    print_step_footer "Web Tools"
}

install_3dprinting() {
    print_step_header "Installing 3D Printing Tools"
    _installPackagesAUR "${AUR_3D_PKGS[@]}"
    print_step_footer "3D Printing Tools"
}

install_xfce4() {
    print_step_header "Installing XFCE4 Packages"
    _installPackagesPacman "${PACMAN_XFCE4_PKGS[@]}"
    _installPackagesAUR "${AUR_XFCE4_PKGS[@]}"
    print_step_footer "XFCE4 Packages"
}

install_file_tools() {
    print_step_header "Installing File Tools"
    _installPackagesPacman thunar mousepad
    _installPackagesAUR thunar-shares-plugin
    print_step_footer "File Tools"
}

install_graphics_card() {
    print_step_header "Graphics Card Setup"
    echo "Which Graphics Card do you have?"
    echo "  1) Intel"
    echo "  2) AMD"
    echo "  3) Nvidia"
    echo "  4) Virtualization (VMware / QEMU)"
    echo "  Defaults to AMD if you choose something else"
    read -rp "Enter choice [1-4]: " GRAPHICSCARD
    case $GRAPHICSCARD in
    1)
        _installPackagesPacman xf86-video-intel mesa vulkan-intel
        ;;
    2)
        _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
        sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
        _update_initramfs
        ;;
    3)
        sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>/dev/null || true
        echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
        _installPackagesPacman nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
        _installPackagesAUR libva-nvidia-driver-git
        _update_initramfs
        ;;
    4)
        echo "Installing virtualization guest drivers (QEMU/virt & VMware)..."
        _installPackagesPacman qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
        _installPackagesAUR xf86-video-vmware
        sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
        sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
        sudo systemctl enable --now vmtoolsd 2>/dev/null || true
        echo "Virtualization drivers installed."
        ;;
    *)
        _installPackagesPacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
        sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
        _update_initramfs
        ;;
    esac
    print_step_footer "Graphics Card Setup"
}

install_fonts() {
    print_step_header "Installing Fonts"
    if [ ! -d ~/.local/share/fonts/ ]; then
        git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
        echo "User fonts installed."
    else
        echo "Fonts folder already exists. Updating..."
        (cd ~/.local/share/fonts && git pull)
    fi
    # Also copy to system if needed (optional)
    if [ -d ~/hyprtk/fonts ]; then
        sudo cp -r ~/hyprtk/fonts/* /usr/share/fonts 2>/dev/null || true
    fi
    print_step_footer "Fonts"
}

install_wallpapers() {
    print_step_header "Installing Wallpapers"
    if [ ! -d ~/Pictures/Wallpapers/ ]; then
        git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
    else
        echo "Wallpapers folder already exists. Updating..."
        (cd ~/Pictures/Wallpapers && git pull)
    fi
    print_step_footer "Wallpapers"
}

install_matuwall() {
    print_step_header "Installing Matuwall"
    if [ -d ~/.local/share/Matuwall ]; then
        echo "Removing existing Matuwall..."
        rm -rf ~/.local/share/Matuwall
    fi
    if [ -f ~/.local/bin/matuwall ]; then
        rm -f ~/.local/bin/matuwall
    fi
    git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall
    cd ~/.local/share/Matuwall || return
    /usr/bin/python -m venv --system-site-packages .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install .
    mkdir -p ~/.local/bin
    ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
    cd -
    print_step_footer "Matuwall"
}

install_hyprviz() {
    print_step_header "Installing HyprViz"
    _installPackagesAUR hyprviz-bin
    print_step_footer "HyprViz"
}

install_sddm_check() {
    print_step_header "Configuring SDDM (Removing others)"
    sudo systemctl disable lightdm lightdm-plymouth 2>/dev/null || true
    sudo systemctl disable gdm gdm-plymouth 2>/dev/null || true
    sudo systemctl disable lxdm lxdm-plymouth 2>/dev/null || true
    sudo systemctl disable slim slim-plymouth 2>/dev/null || true
    sudo systemctl disable kdm kdm-plymouth 2>/dev/null || true
    sudo systemctl disable ly ly-plymouth 2>/dev/null || true
    sudo systemctl enable sddm
    sudo systemctl enable sddm --force 2>/dev/null || true
    if [ ! -d /etc/sddm.conf.d/ ]; then
        sudo mkdir /etc/sddm.conf.d
    fi
    if [ -f ~/hyprtk/sddm/sddm.conf ]; then
        sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
        echo "SDDM config updated."
    else
        echo "Warning: sddm.conf not found – skipping"
    fi
    print_step_footer "SDDM Configuration"
}

install_sddm_grub() {
    print_step_header "Theming SDDM & GRUB"
    if [ ! -d /etc/sddm.conf.d/ ]; then
        sudo mkdir /etc/sddm.conf.d
    fi
    sudo rm -rf /usr/share/grub/themes/*
    sudo rm -rf /boot/grub/themes/*
    if [ -f ~/hyprtk/sddm/sddm.conf ]; then
        sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
    fi
    if [ -f ~/hyprtk/default.png ]; then
        cp ~/hyprtk/default.png ~/.cache/current-wallpaper.png
        if [ -d /usr/share/sddm/themes/Sugar-Candy/Backgrounds ]; then
            sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/
        fi
        if [ -f ~/hyprtk/sddm/theme.conf ]; then
            sudo cp ~/hyprtk/sddm/theme.conf /usr/share/sddm/themes/Sugar-Candy/
        fi
        sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
    fi
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    if [ -f /root/.cache/current-wallpaper.png ]; then
        echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo tee -a /etc/default/grub
    fi
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo tee -a /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    print_step_footer "SDDM & GRUB Theming"
}

install_awww_wrapper() {
    print_step_header "Installing awww wrapper"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/awww" << 'AWWWEOF'
#!/bin/bash
# MASU awww wrapper — runs real awww then triggers pywal pipeline
REAL_AWW=/usr/bin/awww
WALLPAPER="${@: -1}"
"$REAL_AWW" "$@"
[ -f "$WALLPAPER" ] && bash ~/.config/hypr/scripts/wallpaper-colors.sh "$WALLPAPER" &
AWWWEOF
    chmod +x "$HOME/.local/bin/awww"
    if ! grep -q 'local/bin' ~/.zshrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    fi
    if ! grep -q 'local/bin' ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
    if ! grep -q 'wal/sequences' ~/.zshrc 2>/dev/null; then
        echo '(cat ~/.cache/wal/sequences &)' >> ~/.zshrc
    fi
    sudo ln -sf /usr/bin/awww /usr/bin/swww
    sudo ln -sf /usr/bin/awww-daemon /usr/bin/swww-daemon
    print_step_footer "awww wrapper"
}

install_ohmyzsh() {
    print_step_header "Installing Oh-My-Zsh"
    if [ -d ~/.oh-my-zsh ]; then
        echo "Removing existing Oh-My-Zsh..."
        rm -rf ~/.oh-my-zsh
    fi
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
    sudo chsh -s /bin/zsh "$USER"
    chsh -s /bin/zsh
    print_step_footer "Oh-My-Zsh"
}

# ------------------- Distribution-Specific Full Installation Routines -------------------
# Note: install_graphics_card has been removed from these; it will be called once in main.

run_arch() {
    install_system
    install_network
    install_printers
    install_hyprland
    install_hyprviz
    install_media
    install_terminal_tools
    install_file_tools
    install_web_tools
    install_system_tools
    install_3dprinting
    install_fonts
    install_wallpapers
    install_matuwall
    install_sddm_check
    install_sddm_grub
}

run_archbang() {
    install_3dprinting
    install_file_tools
    install_fonts
    install_hyprland
    install_hyprviz
    install_matuwall
    install_media
    install_network
    install_printers
    install_sddm_check
    install_sddm_grub
    install_system
    install_system_tools
    install_terminal_tools
    install_wallpapers
    install_web_tools
    install_xfce4
}

run_archcraft() { run_arch; }
run_archman()   { run_archbang; }
run_bslx()      { run_archbang; }
run_cachyos()   { run_arch; }
run_endeavouros() { run_arch; }
run_garuda()    { run_archbang; }
run_kiro()      { run_arch; }
run_manjaro()   { run_archbang; }
run_mydots()    { run_arch; }
run_rebornos()  { run_arch; }

# ------------------- Main Script Start -------------------

print_step_header "Welcome to the Hyprland & XFCE unified installer"
echo "  by hyprtk (Kori Tk) (2026)"
echo ""
echo "Detected distribution: $DISTRO_ID"
echo ""
echo "This script will install all packages and configure your system."
echo "Please ensure you have a stable internet connection."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort."

# ------------------- Remove leftover packages (distro-specific) -------------------
print_step_header "Removing leftover Packages"
sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true

case $DISTRO_ID in
    archbang)
        sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
        ;;
    bslx)
        sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rcs plasma kde-applications --noconfirm 2>/dev/null || true
        ;;
    kiro)
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
        yay -Rns sddm-git fastfetch-git --noconfirm 2>/dev/null || true
        ;;
    *) ;;
esac
print_step_footer "Removing leftover Packages"

# ------------------- Install AUR helper (if not present) -------------------
print_step_header "Install / Verify AUR Helper"
# Install base-devel and git if missing
_installPackagesPacman base-devel git

# Now select AUR helper (this also installs it if missing)
select_aur_helper
print_step_footer "AUR Helper ready"

# ------------------- Set Timezone -------------------
print_step_header "Setting Timezone"
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true
sudo timedatectl set-local-rtc 0
echo "Timezone set to Europe/London."
print_step_footer "Timezone"

# ------------------- Graphics Card (ONCE) -------------------
install_graphics_card

# ------------------- Install Core Apps (all categories) -------------------
print_step_header "Installing Core Applications"

# Call the distribution-specific full installation routine
case $DISTRO_ID in
    archbang)    run_archbang ;;
    archcraft)   run_archcraft ;;
    archman)     run_archman ;;
    bslx)        run_bslx ;;
    cachyos)     run_cachyos ;;
    endeavouros) run_endeavouros ;;
    garuda)      run_garuda ;;
    kiro)        run_kiro ;;
    manjaro)     run_manjaro ;;
    mydots)      run_mydots ;;
    rebornos)    run_rebornos ;;
    *)           run_arch ;;  # default to Arch
esac

print_step_footer "Core Applications"

# ------------------- Install Pywal16 -------------------
print_step_header "Installing Pywal16"
if [ -f /usr/bin/wal ]; then
    echo "pywal16 already installed."
else
    _installPackagesAUR python-pywal16-git
fi
print_step_footer "Pywal16"

# ------------------- Init Pywal16 and copy wallpaper -------------------
print_step_header "Initiating Pywal16 and copying wallpaper"
wal -i ~/hyprtk/Wallpapers/default.png
cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png

case $DISTRO_ID in
    archbang|bslx)
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
        echo "Wallpaper copied to /boot/grub/"
        ;;
esac

xdg-user-dirs-update --force 2>/dev/null || true
if command -v xdg-user-dirs-gtk-update &>/dev/null; then
    xdg-user-dirs-gtk-update --force 2>/dev/null || true
fi
print_step_footer "Pywal16 initialization"

# ------------------- Generate xfconf via Thunar -------------------
print_step_header "Generating xfconf via Thunar"
thunar &
sleep 3
killall thunar 2>/dev/null || true
echo "xfconf generated."
print_step_footer "xfconf generation"

# ------------------- Enable Services -------------------
print_step_header "Enabling Services"

echo "Enabling Bluetooth..."
sudo systemctl start bluetooth
sudo systemctl enable bluetooth

echo "Enabling Cockpit..."
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
        _update_initramfs
        ;;
    *)
        sudo cp ~/hyprtk/os-release/os-release /usr/lib/
        ;;
esac
sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
sudo systemctl enable --now cockpit.socket
sudo systemctl start cockpit.socket

echo "Enabling Samba..."
sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
sudo systemctl enable smb nmb
sudo systemctl start smb nmb
sudo systemctl restart smb nmb
echo "Samba enabled. Please update interfaces in /etc/samba/smb.conf if needed."

print_step_footer "Services"

# ------------------- Backup hypr config -------------------
backup_hypr

# ------------------- Ensure .config exists -------------------
mkdir -p ~/.config

# ------------------- Create Symbolic Links (no prompts) -------------------
print_step_header "Creating Symbolic Links"

# General
_installSymLink alacritty ~/.config/alacritty ~/hyprtk/alacritty/ ~/.config
_installSymLink ranger ~/.config/ranger ~/hyprtk/ranger/ ~/.config
_installSymLink vim ~/.config/vim ~/hyprtk/vim/ ~/.config
_installSymLink nvim ~/.config/nvim ~/hyprtk/nvim/ ~/.config
_installSymLink starship ~/.config/starship.toml ~/hyprtk/starship/starship.toml ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi ~/hyprtk/rofi/ ~/.config
_installSymLink dunst ~/.config/dunst ~/hyprtk/dunst/ ~/.config
_installSymLink wal ~/.config/wal ~/hyprtk/wal/ ~/.config
_installSymLink btop ~/.config/btop ~/hyprtk/btop/ ~/.config

# GTK
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0/ ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0/ ~/.config/
_installSymLink themes ~/.local/share/themes ~/hyprtk/themes ~/.local/share/
_installSymLink icons ~/.local/share/icons ~/hyprtk/papirus-icons/icons ~/.local/share/

# Xfce
_installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/xfce4 ~/.config/
_installSymLink Thunar ~/.config/Thunar ~/hyprtk/Thunar ~/.config/
_installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/Mousepad ~/.config/

# Hyprland
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
_installSymLink standalone ~/.local/bin ~/hyprtk/standalone/ ~/.local/bin

print_step_footer "Symbolic Links"

# ------------------- Re-init Pywal after symlinks -------------------
wal -i ~/hyprtk/Wallpapers/default.png

# ------------------- Install Oh-My-Zsh -------------------
install_ohmyzsh

# ------------------- Install awww wrapper -------------------
install_awww_wrapper

# ------------------- Root User Config -------------------
print_step_header "Setting up Root User Config"
sudo cp -r ~/hyprtk/root /
echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers
echo "Root config copied and sudo password feedback enabled."
print_step_footer "Root User Config"

# ------------------- Update GRUB for Kiro (if needed) -------------------
if [[ $DISTRO_ID == "kiro" ]]; then
    print_step_header "Updating GRUB (Kiro)"
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    print_step_footer "GRUB Update (Kiro)"
fi

# ------------------- Completion -------------------
print_step_header "Installation Complete!"
echo "DONE!"
echo ""
echo "NEXT: Update the keyboard layout and screen resolution in ~/hyprtk/hypr/hyprland.conf"
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""
print_step_footer "hyprtk Ultimate Installer"

exit 0