#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUM="$SCRIPT_DIR/common/standalone/gum"

DISTRO=""
INITRAMFS_TOOL=""

MAGENTA=5
CYAN=6
WHITE=15
BLACK=0
RED=1
YELLOW=3

gum() {
    "$GUM" "$@"
}

prompt_confirm() {
    gum confirm --prompt.foreground=$MAGENTA "$1" && return 0 || return 1
}

section_header() {
    clear
    gum style \
        --border double \
        --border-foreground $MAGENTA \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$@"
    echo ""
}

sub_header() {
    gum style \
        --foreground $CYAN \
        --bold \
        "$@"
    echo ""
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ID_LOWER=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        case "$ID_LOWER" in
            arch) DISTRO="arch" ;;
            archbang) DISTRO="archbang" ;;
            archcraft) DISTRO="archcraft" ;;
            archman) DISTRO="archman" ;;
            biglinux|bslx) DISTRO="bslx" ;;
            cachyos) DISTRO="cachy" ;;
            endeavouros) DISTRO="endeavour" ;;
            garuda) DISTRO="garuda" ;;
            kiro) DISTRO="kiro" ;;
            manjaro) DISTRO="manjaro" ;;
            rebornos) DISTRO="reborn" ;;
            *)
                if echo "$ID_LIKE" | grep -qi "arch"; then
                    DISTRO="arch"
                else
                    DISTRO="arch"
                fi
                ;;
        esac
    else
        DISTRO="arch"
    fi
}

detect_initramfs() {
    if command -v dracut &>/dev/null; then
        INITRAMFS_TOOL="dracut"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS_TOOL="mkinitcpio"
    else
        INITRAMFS_TOOL="mkinitcpio"
    fi
}

_initramfs_rebuild() {
    if [ "$INITRAMFS_TOOL" = "dracut" ]; then
        dracut --force --regenerate-all 2>/dev/null || dracut --force 2>/dev/null || true
    else
        mkinitcpio -P 2>/dev/null || {
            for p in /etc/mkinitcpio.d/*.preset; do
                [ -f "$p" ] && mkinitcpio -p "$(basename "$p" .preset)" 2>/dev/null || true
            done
        }
    fi
}

_initramfs_add_module() {
    local module_list="$1"
    local conf_name
    conf_name=$(echo "$module_list" | tr ' ' '_')
    if [ "$INITRAMFS_TOOL" = "dracut" ]; then
        echo "add_drivers+=\" $module_list \"" | sudo tee /etc/dracut.conf.d/"${conf_name}".conf >/dev/null
    else
        if grep -q "^MODULES=" /etc/mkinitcpio.conf 2>/dev/null; then
            sudo sed -i "s/^MODULES=(.*)/MODULES=($module_list)/" /etc/mkinitcpio.conf
        else
            echo "MODULES=($module_list)" | sudo tee -a /etc/mkinitcpio.conf >/dev/null
        fi
    fi
}

_installPackagesPacman() {
    toInstall=();
    for pkg; do
        if [[ $(sudo pacman -Qs --color always "${pkg}" | grep "local" | grep "${pkg} ") ]]; then
            continue;
        fi;
        toInstall+=("${pkg}");
    done;
    if [[ "${toInstall[@]}" == "" ]] ; then
        return;
    fi;
    sudo pacman --noconfirm -S "${toInstall[@]}";
}

_installSymLink() {
    name="$1"
    symlink="$2";
    linksource="$3";
    linktarget="$4";
    if [ -L "${symlink}" ]; then
        rm ${symlink}
        ln -s ${linksource} ${linktarget}
    elif [ -d ${symlink} ]; then
        rm -rf ${symlink}/
        ln -s ${linksource} ${linktarget}
    elif [ -f ${symlink} ]; then
        rm ${symlink}
        ln -s ${linksource} ${linktarget}
    else
        ln -s ${linksource} ${linktarget}
    fi
    gum style --foreground $CYAN "  Symlink created: $(basename $linksource)"
}

# === DETECTION ===
detect_distro
detect_initramfs

# === WELCOME ===
section_header \
    "HYPRTK DOTFILES" \
    "Hyprland Desktop Environment Installer"

gum style --foreground $CYAN "  Distribution: $DISTRO"
gum style --foreground $CYAN "  Initramfs:    $INITRAMFS_TOOL"
echo ""

if [ -z "$DISTRO" ]; then
    section_header "SELECT DISTRIBUTION"
    DISTRO=$(gum choose \
        --header.foreground=$MAGENTA \
        --cursor.foreground=$MAGENTA \
        --selected.foreground=$BLACK \
        --selected.background=$MAGENTA \
        --item.foreground=$CYAN \
        arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn)
fi

DISTRO_DIR="$SCRIPT_DIR/distro/$DISTRO"

section_header "DISCLAIMER" \
    "" \
    "This installer configures Hyprland (Wayland) and XFCE (Xorg)." \
    "Both environments will be installed together." \
    "Review the script before running on production systems."

if ! prompt_confirm "Proceed with installation?"; then
    exit 0
fi

# === CONFLICTING PACKAGES ===
section_header "Removing Conflicting Packages"

sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true

if [ "$DISTRO" = "archbang" ]; then
    sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
elif [ "$DISTRO" = "bslx" ]; then
    sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
    sudo pacman -Rcs plasma kde-applications --noconfirm 2>/dev/null || true
elif [ "$DISTRO" = "kiro" ]; then
    sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
    yay -Rns sddm-git fastfetch-git --noconfirm 2>/dev/null || true
fi

gum style --foreground $CYAN "Done."

# === DEPENDENCIES ===
section_header "Installing Dependencies"

sub_header "Setting timezone..."
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true
sudo timedatectl set-local-rtc 0
gum style --foreground $CYAN "Done."

# === YAY ===
section_header "Installing AUR Helper (yay)"

if sudo pacman -Qs yay > /dev/null 2>&1; then
    gum style --foreground $CYAN "yay is already installed."
else
    gum style --foreground $CYAN "Installing yay..."
    _installPackagesPacman "base-devel"
    git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git
    cd ~/Downloads/yay-git
    makepkg -si --noconfirm
    cd "$SCRIPT_DIR"
fi

# === GRAPHICS ===
section_header "Graphics Card Setup"

GPU=$(gum choose \
    --header.foreground=$MAGENTA \
    --cursor.foreground=$MAGENTA \
    --selected.foreground=$BLACK \
    --selected.background=$MAGENTA \
    --item.foreground=$CYAN \
    "Intel" "AMD" "Nvidia")

case $GPU in
    "Intel")
        sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel vulkan-intel;;
    "AMD")
        sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
        _initramfs_add_module "amdgpu"
        _initramfs_rebuild;;
    "Nvidia")
        sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        _initramfs_add_module "nvidia nvidia_modeset nvidia_uvm nvidia_drm"
        echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
        sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva && yay --noconfirm -S libva-nvidia-driver-git
        _initramfs_rebuild;;
esac

gum style --foreground $CYAN "Graphics card configured."

# === CORE PACKAGES ===
if prompt_confirm "Install core packages now?"; then
    section_header "Hyprland"
    sudo pacman -S hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl libadwaita gtk-layer-shell python python-pip python-virtualenv python-gobject gtk4 wob --noconfirm
    yay -S awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb 7zip unzip unrar waybar-git --noconfirm

    section_header "XFCE"
    sudo pacman -S xfce4 xfce4-goodies parole --noconfirm
    yay -S tumbler-extra-thumbnailers --noconfirm

    section_header "File Tools"
    sudo pacman -S thunar mousepad --noconfirm
    yay -S thunar-shares-plugin --noconfirm

    section_header "Web Tools"
    sudo pacman -S chromium --noconfirm
    yay -S brave-bin github-desktop-bin --noconfirm

    section_header "Printer"
    yay -S cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate --noconfirm

    section_header "Network"
    sudo pacman -S networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb gvfs-wsdd ntfs-3g samba --noconfirm

    section_header "Media"
    sudo pacman -S xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg --noconfirm
    yay -S hyprquickframe-git --noconfirm

    section_header "Terminal Tools"
    sudo pacman -S eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim --noconfirm
    yay -S fastfetch --noconfirm

    section_header "System Tools"
    sudo pacman -S timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit --noconfirm
    yay -S gnome-disk-utility --noconfirm

    section_header "System Packages"
    sudo pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker --noconfirm
    sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm || true

    if [ "$DISTRO" = "reborn" ]; then
        yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek tumbler-extra-thumbnailers --noconfirm
    else
        yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers --noconfirm
    fi

    section_header "Papirus Folders"
    wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh

    section_header "HyprViz (Config Tool)"
    git clone https://aur.archlinux.org/hyprviz-bin.git ~/Downloads/hyprviz-bin || true
    cd ~/Downloads/hyprviz-bin
    makepkg -si --noconfirm || true
    cd "$SCRIPT_DIR"

    section_header "Display Manager (SDDM)"
    sudo pacman -S --noconfirm sddm
    if [ -f "$SCRIPT_DIR/scripts/rm-dm-managers.sh" ]; then
        bash "$SCRIPT_DIR/scripts/rm-dm-managers.sh"
    fi
    if [ ! -d /etc/sddm.conf.d/ ]; then
        sudo mkdir /etc/sddm.conf.d
    fi
    sudo cp "$SCRIPT_DIR/common/sddm/sddm.conf" /etc/sddm.conf.d/

    section_header "GRUB & SDDM Theming"
    sudo rm -rf /usr/share/grub/themes/* 2>/dev/null || true
    sudo rm -rf /boot/grub/themes/* 2>/dev/null || true
    cp "$SCRIPT_DIR/default.png" ~/.cache/current-wallpaper.png
    sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/ 2>/dev/null || true
    sudo cp "$SCRIPT_DIR/common/sddm/theme.conf" /usr/share/sddm/themes/Sugar-Candy/ 2>/dev/null || true
    sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo tee -a /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg || true
    sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

    section_header "Matuwall (Wallpaper Picker)"
    git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall || true
    cd ~/.local/share/Matuwall
    /usr/bin/python -m venv --system-site-packages .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install .
    mkdir -p ~/.local/bin
    ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
    cd "$SCRIPT_DIR"

    section_header "awww Wrapper"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/awww" << 'AWWWEOF'
#!/bin/bash
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
    sudo ln -s /usr/bin/awww /usr/bin/swww 2>/dev/null || true
    sudo ln -s /usr/bin/awww-daemon /usr/bin/swww-daemon 2>/dev/null || true

    section_header "Core Packages Installed"
    sleep 1
fi

# === PYwal16 ===
section_header "Pywal16 (Dynamic Color Scheme)"
if [ -f /usr/bin/wal ]; then
    gum style --foreground $CYAN "pywal16 already installed."
else
    yay --noconfirm -S python-pywal16-git
fi

# === WALLPAPERS ===
section_header "Wallpapers"
if prompt_confirm "Clone wallpapers repository? (No = copy defaults)"; then
    if [ ! -d ~/Pictures/Wallpapers/ ]; then
        git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
    fi
else
    if [ ! -d ~/Pictures/Wallpapers/ ]; then
        mkdir -p ~/Pictures/Wallpapers
    fi
    cp "$SCRIPT_DIR/common/Wallpapers/"* ~/Pictures/Wallpapers/
fi

# === FONTS ===
section_header "Fonts"
if prompt_confirm "Clone fonts repository? (No = copy system fonts)"; then
    if [ ! -d ~/.local/share/fonts/ ]; then
        git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
    fi
else
    if [ ! -d ~/.local/share/fonts/ ]; then
        mkdir -p ~/.local/share/fonts
    fi
    sudo cp -r "$SCRIPT_DIR/common/fonts/"* /usr/share/fonts/
    sudo cp -r ~/.local/share/fonts/* /usr/share/fonts/ 2>/dev/null || true
fi

# === ROOT ICONS ===
section_header "Root Icons"
wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh

# === PYWAL16 INIT ===
section_header "Initializing Pywal16"
wal -i "$SCRIPT_DIR/default.png"
cp "$SCRIPT_DIR/default.png" ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
if [ "$DISTRO" = "bslx" ]; then
    sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
fi
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force

# === HYPRLAND CONFIG ===
section_header "Hyprland Configuration"
if ! prompt_confirm "Proceed with Hyprland configuration?"; then
    exit 0
fi

sub_header "Thunar (XFCE config generation)..."
thunar &
sleep 3
killall thunar 2>/dev/null || true

sub_header "Bluetooth..."
sudo systemctl start bluetooth
sudo systemctl enable bluetooth

sub_header "Cockpit..."
if [ "$DISTRO" = "cachy" ]; then
    sudo cp "$DISTRO_DIR/os-release/os-release" /usr/lib/
    sudo cp "$DISTRO_DIR/os-release/os-release" /run/systemd/propagate/.os-release-stage/ 2>/dev/null || true
    sudo cp "$DISTRO_DIR/os-release/os-release" /run/user/$UID/systemd/propagate/.os-release-stage/ 2>/dev/null || true
    sudo cp "$DISTRO_DIR/os-release/cachyos-branding" /usr/share/libalpm/scripts/ 2>/dev/null || true
    sudo bash /usr/share/libalpm/scripts/cachyos-branding 2>/dev/null || true
elif [ "$DISTRO" = "archbang" ]; then
    sudo cp "$DISTRO_DIR/os-release/os-release" /etc/
else
    sudo cp "$DISTRO_DIR/os-release/os-release" /usr/lib/
fi
if [ "$DISTRO" = "arch" ]; then
    sudo cp "$SCRIPT_DIR/common/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
    _initramfs_rebuild
fi
sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
sudo systemctl enable --now cockpit.socket 2>/dev/null || true
sudo systemctl start cockpit.socket 2>/dev/null || true

sub_header "Samba..."
sudo cp "$SCRIPT_DIR/common/smb/smb.conf" /etc/samba/
sudo systemctl enable smb nmb 2>/dev/null || true
sudo systemctl start smb nmb 2>/dev/null || true
sudo systemctl restart smb nmb 2>/dev/null || true

gum style --foreground $CYAN "Update the interfaces section of /etc/samba/smb.conf with your IP."
sleep 2

gum style --foreground $YELLOW "If you use an NVIDIA card, configure it in:"
gum style --foreground $CYAN "  ~/hyprtk/hypr/nvidia.lua"
sleep 3

# === DOTFILES ===
section_header "Dotfiles Deployment" \
    "" \
    "Symbolic links will be created from ~/hyprtk to ~/.config/" \
    "You will be prompted before each one."

if ! prompt_confirm "Deploy dotfiles now?"; then
    section_header "Installation Complete (Skipped Dotfiles)"
    gum style --foreground $CYAN "Next: reboot your system."
    exit 0
fi

if [ ! -d ~/.config ]; then
    mkdir ~/.config
fi

if [ "$DISTRO" = "endeavour" ]; then
    mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
fi

sub_header "General Configs"
_installSymLink alacritty ~/.config/alacritty "$SCRIPT_DIR/common/alacritty/" ~/.config
_installSymLink ranger ~/.config/ranger "$SCRIPT_DIR/common/ranger/" ~/.config
_installSymLink vim ~/.config/vim "$SCRIPT_DIR/common/vim/" ~/.config
_installSymLink nvim ~/.config/nvim "$SCRIPT_DIR/common/nvim/" ~/.config
_installSymLink starship ~/.config/starship.toml "$SCRIPT_DIR/common/starship/starship.toml" ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi "$SCRIPT_DIR/common/rofi/" ~/.config
_installSymLink dunst ~/.config/dunst "$SCRIPT_DIR/common/dunst/" ~/.config
_installSymLink wal ~/.config/wal "$SCRIPT_DIR/common/wal/" ~/.config
_installSymLink btop ~/.config/btop "$SCRIPT_DIR/common/btop/" ~/.config

section_header "Pywal16 Template Regeneration"
wal -i "$SCRIPT_DIR/default.png"

sub_header "GTK"
_installSymLink gtk-3.0 ~/.config/gtk-3.0 "$SCRIPT_DIR/common/gtk/gtk-3.0/" ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 "$SCRIPT_DIR/common/gtk/gtk-4.0/" ~/.config/
_installSymLink themes ~/.local/share/themes "$SCRIPT_DIR/common/themes" ~/.local/share/
_installSymLink icons ~/.local/share/icons "$SCRIPT_DIR/common/papirus-icons/icons" ~/.local/share/

sub_header "XFCE"
_installSymLink xfce4 ~/.config/xfce4 "$DISTRO_DIR/xfce4" ~/.config/
_installSymLink Thunar ~/.config/Thunar "$SCRIPT_DIR/common/Thunar" ~/.config/
_installSymLink Mousepad ~/.config/Mousepad "$SCRIPT_DIR/common/Mousepad" ~/.config/

sub_header "Hyprland"
if [ "$DISTRO" != "endeavour" ]; then
    mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
fi
_installSymLink hypr ~/.config/hypr "$SCRIPT_DIR/hypr/" ~/.config
_installSymLink fastfetch ~/.config/fastfetch "$SCRIPT_DIR/common/fastfetch/" ~/.config
_installSymLink waybar ~/.config/waybar "$SCRIPT_DIR/common/waybar/" ~/.config
_installSymLink swaylock ~/.config/swaylock "$SCRIPT_DIR/common/swaylock/" ~/.config
_installSymLink swappy ~/.config/swappy "$SCRIPT_DIR/common/swappy/" ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout "$SCRIPT_DIR/common/hyprlogout/" ~/.config
_installSymLink waypaper ~/.config/waypaper "$SCRIPT_DIR/common/waypaper/" ~/.config
_installSymLink zshrc ~/.config/zshrc "$SCRIPT_DIR/common/zshrc/" ~/.config
_installSymLink ohmyposh ~/.config/ohmyposh "$SCRIPT_DIR/common/ohmyposh/" ~/.config
_installSymLink matuwall ~/.config/matuwall "$SCRIPT_DIR/common/matuwall/" ~/.config
_installSymLink wob ~/.config/wob "$SCRIPT_DIR/common/wob/" ~/.config
mkdir -p ~/.local/bin

sub_header "ZSH"
sudo pacman -S zsh --noconfirm
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

sub_header "ZSH Plugins"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting

sub_header "ZSH Config"
_installSymLink .zshrc ~/.zshrc "$SCRIPT_DIR/.zshrc" ~/.zshrc
sudo chsh -s /bin/zsh
chsh -s /bin/zsh

_installSymLink standalone ~/.local/bin "$SCRIPT_DIR/common/standalone/" ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/common/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

_installSymLink hyprpicker ~/.config/hypr/scripts/hyprpicker-color "$SCRIPT_DIR/common/hyprpicker/colorpicker.sh" ~/.config/hypr/scripts/hyprpicker-color

rm -R $HOME/dotfiles 2>/dev/null || true

sub_header "Root User Config"
sudo cp -r "$SCRIPT_DIR/common/root/" /
echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers

# === COMPLETE ===
section_header \
    "Installation Complete" \
    "" \
    "Next: Update keyboard layout in ~/hyprtk/hypr/hyprland.lua" \
    "Then reboot your system."
