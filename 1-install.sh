#!/bin/bash

#########################################################
#                                                       #
#          Hyprtk-On-Arch - Unified Installer           #
#                                                       #
#  Merged from 11 Arch-based distributions:             #
#  Arch, ArchBang, ArchCraft, ArchMan, BSLx, CachyOS,   #
#  EndeavourOS, Garuda, Kiro, Manjaro, RebornOS         #
#                                                       #
#  by hyprtk (Kori Tk) (2026)                           #
#                                                       #
#########################################################

export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

#########################################################
#                                                       #
#                   Error Handling                      #
#                                                       #
#########################################################

set -o pipefail

error_trap() {
    local line=$1
    local cmd=$2
    local code=$3
    echo ""
    echo "  ERROR: Command exited with code $code at line $line"
    echo "  Command: $cmd"
    echo "  See install log for details."
    echo ""
}

trap 'error_trap $LINENO "$BASH_COMMAND" $?' ERR

require_file() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "  ERROR: Required file not found: $path"
        echo "  The installer may be corrupted or incomplete."
        exit 1
    fi
}

warn_missing() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "  WARNING: Optional file not found: $path (skipping)"
        return 1
    fi
    return 0
}

run_critical() {
    if ! "$@"; then
        echo "  ERROR: Critical step failed. Aborting."
        exit 1
    fi
}

run_optional() {
    "$@" 2>/dev/null || true
}

# Pre-flight check for installer itself
if [ ! -f "$SCRIPT_DIR/1-install.sh" ]; then
    echo "  ERROR: Installer file not found."
    exit 1
fi

#########################################################
#                                                       #
#                   Install Log Setup                   #
#                                                       #
#########################################################

INSTALL_LOG="$HOME/hyprtk-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$INSTALL_LOG") 2>&1
echo "Install log: $INSTALL_LOG"

#########################################################
#                                                       #
#                   Distro Detection                    #
#                                                       #
#########################################################

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    elif [ -f /usr/lib/os-release ]; then
        . /usr/lib/os-release
        echo "${ID}"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)

case "$DISTRO" in
    arch)        DISTRO_NAME="Arch Linux" ;;
    endeavouros) DISTRO_NAME="EndeavourOS" ;;
    garuda)      DISTRO_NAME="Garuda Linux" ;;
    manjaro)     DISTRO_NAME="Manjaro" ;;
    cachyos)     DISTRO_NAME="CachyOS" ;;
    archbang)    DISTRO_NAME="ArchBang" ;;
    archcraft)   DISTRO_NAME="ArchCraft" ;;
    archman)     DISTRO_NAME="ArchMan" ;;
    rebornos)    DISTRO_NAME="RebornOS" ;;
    bslx)        DISTRO_NAME="BSLx" ;;
    kiro)        DISTRO_NAME="Kiro" ;;
    *)           DISTRO_NAME="Unknown" ;;
esac

#########################################################
#                                                       #
#                Initramfs Detection                    #
#                                                       #
#########################################################

detect_initramfs() {
    if command -v dracut &>/dev/null; then
        echo "dracut"
    elif command -v mkinitcpio &>/dev/null; then
        echo "mkinitcpio"
    else
        echo "none"
    fi
}

INITRAMFS_TOOL=$(detect_initramfs)

#########################################################
#                                                       #
#                 Header / Log Functions                #
#                                                       #
#########################################################

print_header() {
    local text="$1"
    local len=${#text}
    local padding=$(( (51 - len) / 2 ))
    local leftpad=""
    local rightpad=""

    if [ $padding -gt 0 ]; then
        printf -v leftpad '%*s' "$padding" ''
    fi
    local remaining=$(( 51 - len - padding ))
    if [ $remaining -gt 0 ]; then
        printf -v rightpad '%*s' "$remaining" ''
    fi

    echo ""
    echo "#########################################################"
    echo "#                                                       #"
    echo "#  ${leftpad}${text}${rightpad}  #"
    echo "#                                                       #"
    echo "#########################################################"
    echo ""
}

print_subheader() {
    echo ""
    echo "-------------------------------------------------"
    echo "  $1"
    echo "-------------------------------------------------"
    echo ""
}

#########################################################
#                                                       #
#              Initramfs Rebuild Function                #
#                                                       #
#########################################################

rebuild_initramfs() {
    local modules="$1"

    if [ "$INITRAMFS_TOOL" = "dracut" ]; then
        if [ -n "$modules" ]; then
            echo "force_drivers+=\" $modules \"" | sudo tee /etc/dracut.conf.d/installer.conf
        fi
        if ! sudo dracut --force --regenerate-all; then
            echo "  WARNING: dracut initramfs rebuild failed. Continuing anyway."
        else
            print_subheader "initramfs rebuilt with dracut"
        fi

    elif [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
        if [ -n "$modules" ]; then
            sudo sed -i "s/MODULES=()/MODULES=($modules)/" /etc/mkinitcpio.conf 2>/dev/null || true
            if ! sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img; then
                echo "  WARNING: mkinitcpio initramfs rebuild failed. Continuing anyway."
            fi
        else
            if ! sudo mkinitcpio -P; then
                echo "  WARNING: mkinitcpio initramfs rebuild failed. Continuing anyway."
            fi
        fi
        print_subheader "initramfs rebuilt with mkinitcpio"

    else
        echo "  WARNING: No initramfs tool found (dracut/mkinitcpio). Skipping initramfs rebuild."
    fi
}

#########################################################
#                                                       #
#                   Library Functions                   #
#                                                       #
#########################################################

_isInstalledPacman() {
    package="$1"
    check="$(sudo pacman -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} ")"
    if [ -n "${check}" ]; then
        echo 0
        return
    fi
    echo 1
    return
}

_isInstalledYay() {
    package="$1"
    check="$(yay -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} ")"
    if [ -n "${check}" ]; then
        echo 0
        return
    fi
    echo 1
    return
}

_installPackagesPacman() {
    toInstall=()
    for pkg; do
        if [[ $(_isInstalledPacman "${pkg}") == 0 ]]; then
            echo "${pkg} is already installed."
            continue
        fi
        toInstall+=("${pkg}")
    done
    if [[ "${toInstall[@]}" == "" ]]; then
        return
    fi
    printf "Packages not installed:\n%s\n" "${toInstall[@]}"
    sudo pacman --noconfirm -S "${toInstall[@]}" 2>/dev/null || true
}

_installPackagesYay() {
    toInstall=()
    for pkg; do
        if [[ $(_isInstalledYay "${pkg}") == 0 ]]; then
            echo "${pkg} is already installed."
            continue
        fi
        toInstall+=("${pkg}")
    done
    if [[ "${toInstall[@]}" == "" ]]; then
        return
    fi
    printf "AUR packages not installed:\n%s\n" "${toInstall[@]}"
    yay --noconfirm -S "${toInstall[@]}" 2>/dev/null || true
}

_installSymLink() {
    name="$1"
    symlink="$2"
    linksource="$3"
    linktarget="$4"

    while true; do
        read -p "DO YOU WANT TO INSTALL ${name}? (Existing hyprtk will be removed!) (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                if [ -L "${symlink}" ]; then
                    rm -f "${symlink}" 2>/dev/null || true
                    ln -s "${linksource}" "${linktarget}"
                    echo "Symlink ${linksource} -> ${linktarget} created."
                elif [ -d "${symlink}" ]; then
                    rm -rf "${symlink}" 2>/dev/null || true
                    ln -s "${linksource}" "${linktarget}"
                    echo "Symlink for directory ${linksource} -> ${linktarget} created."
                elif [ -f "${symlink}" ]; then
                    rm -f "${symlink}" 2>/dev/null || true
                    ln -s "${linksource}" "${linktarget}"
                    echo "Symlink to file ${linksource} -> ${linktarget} created."
                else
                    ln -s "${linksource}" "${linktarget}"
                    echo "New symlink ${linksource} -> ${linktarget} created."
                fi
            break;;
            [Nn]* )
                echo ""
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

#########################################################
#                                                       #
#              Inlined Package Functions                #
#                                                       #
#########################################################

install_hyprland() {
    print_subheader "Hyprland"
    sudo pacman -S hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl libadwaita gtk-layer-shell python python-pip python-virtualenv python-gobject gtk4 wob --noconfirm
    yay -S awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb 7zip unzip unrar waybar-git --noconfirm
}

install_xfce4() {
    print_subheader "XFCE4"
    sudo pacman -S xfce4 xfce4-goodies parole --noconfirm
    yay -S tumbler-extra-thumbnailers --noconfirm
}

install_filetools() {
    print_subheader "File Tools"
    sudo pacman -S thunar mousepad --noconfirm
    yay -S thunar-shares-plugin --noconfirm
}

install_webtools() {
    print_subheader "WebTools"
    sudo pacman -S chromium --noconfirm
    yay -S brave-bin github-desktop-bin --noconfirm
}

install_printers() {
    print_subheader "Printer Packages"
    yay -S cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate --noconfirm
}

install_network() {
    print_subheader "Network Packages"
    sudo pacman -S networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb gvfs-wsdd ntfs-3g samba --noconfirm
}

install_media() {
    print_subheader "Media Packages"
    sudo pacman -S xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg --noconfirm
    yay -S hyprquickframe-git --noconfirm
}

install_terminaltools() {
    print_subheader "Terminal Tools"
    sudo pacman -S eza micro xfce4-terminal btop alacritty kitty starship ranger nano neovim --noconfirm
    yay -S fastfetch --noconfirm
}

install_systemtools() {
    print_subheader "System Tools"
    sudo pacman -S timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit wget --noconfirm
    yay -S gnome-disk-utility --noconfirm
}

install_system() {
    print_subheader "System Packages"
    sudo pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker --noconfirm
    sudo pacman -S $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null) --noconfirm 2>/dev/null || true

    local YAY_PKGS="bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek tumbler-extra-thumbnailers"

    if [ "$DISTRO" != "rebornos" ]; then
        YAY_PKGS="$YAY_PKGS pamac-all libpamac-full pamac-cli"
    fi

    yay -S $YAY_PKGS --noconfirm 2>/dev/null || echo "  WARNING: Some AUR packages failed to install. Continuing."

    print_subheader "Papirus Folders Install"
    if ! wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh 2>/dev/null; then
        echo "  WARNING: Papirus folders install failed (network issue?). Continuing."
    fi
}

install_hyprviz() {
    print_subheader "HyprViz"
    mkdir -p "$HOME/Downloads/yay-git/src"
    cd "$HOME/Downloads/yay-git/src"
    if [ -d hyprviz-bin ]; then
        rm -rf hyprviz-bin
    fi
    if ! git clone https://aur.archlinux.org/hyprviz-bin.git; then
        echo "  WARNING: Failed to clone hyprviz-bin. Skipping."
        cd "$SCRIPT_DIR"
        return
    fi
    cd hyprviz-bin
    if ! makepkg -si --noconfirm; then
        echo "  WARNING: Failed to build hyprviz-bin. Skipping."
    fi
    cd "$SCRIPT_DIR"
}

install_sddm_check() {
    print_subheader "SDDM Check"
    echo "  Removing other display managers..."
    sudo pacman -S --noconfirm sddm 2>/dev/null || true
    for dm in lightdm lightdm-plymouth gdm gdm-plymouth lxdm lxdm-plymouth slim slim-plymouth kdm kdm-plymouth ly ly-plymouth; do
        sudo systemctl disable "$dm" 2>/dev/null || true
    done
    sudo systemctl enable sddm 2>/dev/null || true
    sudo systemctl enable sddm --force 2>/dev/null || true
    echo "  Switched to SDDM."

    if [ ! -d /etc/sddm.conf.d/ ]; then
        sudo mkdir /etc/sddm.conf.d
        echo "Folder /etc/sddm.conf.d created."
    fi

    if [ -f "$SCRIPT_DIR/sddm/sddm.conf" ]; then
        sudo cp "$SCRIPT_DIR/sddm/sddm.conf" /etc/sddm.conf.d/
        echo "File /etc/sddm.conf.d/sddm.conf updated."
    else
        echo "  WARNING: sddm.conf not found. Skipping SDDM config."
    fi
}

install_sddmgrub() {
    print_subheader "System Theming"

    if [ ! -d /etc/sddm.conf.d/ ]; then
        sudo mkdir /etc/sddm.conf.d
        echo "Folder /etc/sddm.conf.d created."
    fi

    sudo rm -rf /usr/share/grub/themes/* 2>/dev/null || true
    sudo rm -rf /boot/grub/themes/* 2>/dev/null || true

    if [ -f "$SCRIPT_DIR/sddm/sddm.conf" ]; then
        sudo cp "$SCRIPT_DIR/sddm/sddm.conf" /etc/sddm.conf.d/
        echo "File /etc/sddm.conf.d/sddm.conf updated."
    fi

    if [ -f "$SCRIPT_DIR/default.png" ]; then
        cp "$SCRIPT_DIR/default.png" ~/.cache/current-wallpaper.png
        run_optional sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/
        run_optional sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
        echo "Current wallpaper copied into SDDM theme folder"
    fi

    if [ -f "$SCRIPT_DIR/sddm/theme.conf" ]; then
        run_optional sudo cp "$SCRIPT_DIR/sddm/theme.conf" /usr/share/sddm/themes/Sugar-Candy/
        echo "File theme.conf updated in /usr/share/sddm/themes/Sugar-Candy/"
    fi

    print_subheader "GRUB Theme Configuration"

    run_optional sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

    sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub 2>/dev/null || true
    sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub 2>/dev/null || true
    sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub 2>/dev/null || true

    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo tee -a /etc/default/grub >/dev/null

    if ! sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
        echo "  WARNING: GRUB config update failed. Continuing anyway."
    fi

    run_optional sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

    echo "GRUB and SDDM updated with current wallpaper"
}

install_matuwall() {
    print_subheader "Matuwall"
    sleep 2
    echo "Installing Matuwall wallpaper picker..."

    if [ -d ~/.local/share/Matuwall ]; then
        echo "Matuwall directory already exists. Skipping clone."
    else
        if ! git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall; then
            echo "  WARNING: Failed to clone Matuwall. Skipping."
            return
        fi
    fi

    cd ~/.local/share/Matuwall
    /usr/bin/python -m venv --system-site-packages .venv 2>/dev/null || true
    source .venv/bin/activate 2>/dev/null || true
    pip install --upgrade pip 2>/dev/null || true
    if ! pip install . 2>/dev/null; then
        echo "  WARNING: Failed to install Matuwall Python package. Skipping."
        cd "$SCRIPT_DIR"
        return
    fi
    mkdir -p ~/.local/bin
    ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall 2>/dev/null || true
    cd "$SCRIPT_DIR"
    echo "Matuwall installed!"
    sleep 2
}

install_wallpapers() {
    print_subheader "Wallpapers"
    while true; do
        read -p "Do you want to clone the wallpapers? If not, the script will install 3 default wallpapers to ~/Pictures/Wallpapers/ (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                if [ -d ~/Pictures/Wallpapers/ ]; then
                    echo "Wallpaper folder already exists."
                else
                    git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
                    echo "Wallpapers installed."
                fi
                echo "Wallpapers installed."
            break;;
            [Nn]* )
                if [ -d ~/Pictures/Wallpapers/ ]; then
                    echo "Wallpapers folder already exists."
                else
                    mkdir ~/Pictures/Wallpapers
                fi
                cp "$SCRIPT_DIR/Wallpapers/"* ~/Pictures/Wallpapers
                echo "Default wallpapers installed."
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

install_fonts() {
    print_subheader "Fonts"
    while true; do
        read -p "Do you want to clone the fonts? ~/fonts (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                if [ -d ~/.local/share/fonts/ ]; then
                    echo "Fonts folder already exists."
                else
                    if git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts 2>/dev/null; then
                        echo "User fonts installed."
                    else
                        echo "  WARNING: Font clone failed. Falling back to system install."
                        mkdir -p ~/.local/share/fonts
                        run_optional sudo cp -r "$SCRIPT_DIR/fonts/"* /usr/share/fonts
                    fi
                fi
            break;;
            [Nn]* )
                if [ -d ~/.local/share/fonts/ ]; then
                    echo "Fonts folder already exists."
                else
                    mkdir -p ~/.local/share/fonts
                fi
                if [ -d "$SCRIPT_DIR/fonts" ]; then
                    run_optional sudo cp -r "$SCRIPT_DIR/fonts/"* /usr/share/fonts
                fi
                run_optional sudo cp -r ~/.local/share/fonts/* /usr/share/fonts
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
    echo "Fonts installed."
}

install_3dprinting() {
    print_subheader "3D Printing"
    yay -S orca-slicer-bin bambustudio-bin --noconfirm
}

install_awww_wrapper() {
    print_subheader "awww Wrapper"
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

    run_optional sudo ln -sf /usr/bin/awww /usr/bin/swww
    run_optional sudo ln -sf /usr/bin/awww-daemon /usr/bin/swww-daemon
    echo "awww wrapper installed!"
}

#########################################################
#                                                       #
#              Graphics Card Selection                  #
#                                                       #
#########################################################

select_graphics_card() {
    echo ""
    echo "#########################################################"
    echo "#                                                       #"
    echo "#            Which Graphics Card do you have?           #"
    echo "#                                                       #"
    echo "#########################################################"
    echo ""
    echo "  1) Intel"
    echo "  2) AMD"
    echo "  3) Nvidia"
    echo "  4) Virtualization (QEMU/VMware)"
    echo ""
    echo "  Defaults to AMD if you choose something else"
    echo ""
    read GRAPHICSCARD

    case $GRAPHICSCARD in
        1)
            sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
            ;;
        2)
            sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            rebuild_initramfs "amdgpu"
            ;;
        3)
            sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
            sudo grub-mkconfig -o /boot/grub/grub.cfg

            if [ "$INITRAMFS_TOOL" = "dracut" ]; then
                echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf
            else
                sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
            fi

            echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
            sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
            yay --noconfirm -S libva-nvidia-driver-git
            rebuild_initramfs ""
            ;;
        4)
            _installPackagesPacman qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
            _installPackagesYay xf86-video-vmware
            sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
            sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
            sudo systemctl enable --now vmtoolsd 2>/dev/null || true
            ;;
        *)
            sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            rebuild_initramfs "amdgpu"
            ;;
    esac

    echo ""
    print_header "Graphics Card Drivers Installed"
}

#########################################################
#                                                       #
#            Distro-Specific Actions                    #
#                                                       #
#########################################################

run_distro_specific_pre() {
    case "$DISTRO" in
        kiro)
            print_subheader "Kiro: Removing XFCE4 and conflicting packages"
            sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm
            yay -Rns sddm-git fastfetch-git --noconfirm
            sleep 5
            ;;
    esac
}

run_distro_specific_os_release() {
    local os_release_src="$SCRIPT_DIR/distro/$DISTRO/os-release/os-release"

    case "$DISTRO" in
        arch)
            sudo cp "$os_release_src" /usr/lib/
            ;;
        archbang)
            sudo cp "$os_release_src" /etc/
            ;;
        cachyos)
            sudo cp "$os_release_src" /run/systemd/propagate/.os-release-stage/
            sudo cp "$os_release_src" /run/user/$UID/systemd/propagate/.os-release-stage/
            if [ -f "$SCRIPT_DIR/distro/cachy/os-release/cachyos-branding" ]; then
                sudo cp "$SCRIPT_DIR/distro/cachy/os-release/cachyos-branding" /usr/share/libalpm/scripts/
                sudo bash /usr/share/libalpm/scripts/cachyos-branding
            fi
            ;;
        *)
            sudo cp "$os_release_src" /usr/lib/
            ;;
    esac
}

install_plymouth() {
    print_subheader "Plymouth Boot Splash"

    if ! command -v plymouth &>/dev/null; then
        sudo pacman -S plymouth --noconfirm
    fi

    local THEME_DIR="/usr/share/plymouth/themes/Hyprtk-Plymouth"
    sudo mkdir -p "$THEME_DIR"
    sudo cp "$SCRIPT_DIR/plymouth/"* "$THEME_DIR/"

    sudo cp "$SCRIPT_DIR/splash/splash-arch.png" "$THEME_DIR/splash-arch.png"

    if [ -f /etc/plymouth/plymouthd.conf ]; then
        sudo sed -i 's/^Theme=.*/Theme=Hyprtk-Plymouth/' /etc/plymouth/plymouthd.conf
    else
        echo -e "[Daemon]\nTheme=Hyprtk-Plymouth" | sudo tee /etc/plymouth/plymouthd.conf
    fi

    if [ "$INITRAMFS_TOOL" = "dracut" ]; then
        echo 'add_dracutmodules+=" plymouth "' | sudo tee /etc/dracut.conf.d/plymouth.conf
    elif [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
        if grep -q "^HOOKS=" /etc/mkinitcpio.conf; then
            sudo sed -i 's/^HOOKS=.*/HOOKS=(base udev plymouth block filesystems)/' /etc/mkinitcpio.conf
        fi
    fi

    rebuild_initramfs ""

    print_subheader "Plymouth Hyprtk-Plymouth theme installed and configured"
}

run_distro_specific_splash() {
    if [ -f "$SCRIPT_DIR/splash/splash-arch.bmp" ]; then
        sudo cp "$SCRIPT_DIR/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        print_subheader "Boot splash image installed"
    elif [ -f "$SCRIPT_DIR/distro/arch/splash/splash-arch.bmp" ]; then
        sudo cp "$SCRIPT_DIR/distro/arch/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        print_subheader "Boot splash image installed"
    fi
}

run_distro_specific_post_wallpaper() {
    case "$DISTRO" in
        bslx)
            if [ -f ~/.cache/current-wallpaper.png ]; then
                sudo cp ~/.cache/current-wallpaper.png /boot/grub/
            fi
            ;;
    esac
}

run_distro_specific_symlinks() {
    case "$DISTRO" in
        endeavouros|garuda|archbang|archcraft|archman|bslx|cachyos|kiro|manjaro|rebornos)
            if [ -d ~/.config/hypr ]; then
                mv ~/.config/hypr ~/.config/hypr-old
                echo "Existing hypr config moved to ~/.config/hypr-old"
            fi
            ;;
    esac
}

run_distro_specific_post_symlinks() {
    case "$DISTRO" in
        kiro)
            if [ -f "$SCRIPT_DIR/scripts/grudupdater.sh" ]; then
                echo "  Running Kiro GRUB updater..."
                sh "$SCRIPT_DIR/scripts/grudupdater.sh"
            else
                echo "  Note: scripts/grudupdater.sh not found. Skipping Kiro-specific GRUB update."
            fi
            ;;
    esac
}

run_distro_specific_final() {
    case "$DISTRO" in
        rebornos)
            echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers
            ;;
        *)
            echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers
            ;;
    esac
}

#########################################################
#                                                       #
#                  Welcome Section                      #
#                                                       #
#########################################################

print_header "Hyprland & XFCE Installer for $DISTRO_NAME"

echo ""
echo "  Detected distribution: $DISTRO_NAME (ID: $DISTRO)"
echo "  Initramfs tool: $INITRAMFS_TOOL"
echo "  Install log: $INSTALL_LOG"
echo ""
echo "  I have chosen as my preference to install both Hyprland and XFCE."
echo "  If you choose No on either, the installer will fail and close."
echo "  I chose it this way so if one environment has problems,"
echo "  I still have the other to boot to. Enjoy!"
echo ""
echo "  You will now be asked to enter your Root password to proceed."
echo ""
sleep 2

sudo echo "Root access confirmed."

#########################################################
#                                                       #
#              Removing Leftover Packages               #
#                                                       #
#########################################################

print_header "Removing Leftover Packages"
sleep 2

case "$DISTRO" in
    bslx)
        sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rcs plasma kde-applications --noconfirm
        ;;
    *)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rns plasma kde-applications --noconfirm
        ;;
esac

case "$DISTRO" in
    archbang)
        sudo pacman -Rns swaylock --noconfirm
        ;;
esac

run_distro_specific_pre

#########################################################
#                                                       #
#           Set Timezone                                #
#                                                       #
#########################################################

print_header "Set Timezone"
echo "  Setting timezone to Europe/London..."
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true
sudo timedatectl set-local-rtc 0
echo "  Timezone configured."

#########################################################
#                                                       #
#                     Install Yay                       #
#                                                       #
#########################################################

print_header "Install Yay"

if sudo pacman -Qs yay > /dev/null ; then
    echo "yay is installed. You can proceed with the installation"
else
    echo "yay is not installed and will be installed now!"
    _installPackagesPacman "base-devel"
    if ! git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git; then
        echo "  ERROR: Failed to clone yay from AUR. Aborting."
        exit 1
    fi
    cd ~/Downloads/yay-git
    if ! makepkg -si --noconfirm; then
        echo "  ERROR: Failed to build yay from AUR. Aborting."
        exit 1
    fi
    cd "$SCRIPT_DIR"
fi

print_header "Yay is Installed"

#########################################################
#                                                       #
#              User Confirmation                        #
#                                                       #
#########################################################

while true; do
    read -p "DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            echo "Installation started."
        break;;
        [Nn]* )
            exit;
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done

#########################################################
#                                                       #
#              Graphics Card Selection                  #
#                                                       #
#########################################################

select_graphics_card
sleep 2

#########################################################
#                                                       #
#              Core Apps Confirmation                   #
#                                                       #
#########################################################

while true; do
    read -p "DO YOU WANT TO INSTALL THE CORE APPS NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            echo "Installation started."
        break;;
        [Nn]* )
            echo "Installation is Aborted"
            exit;
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done

#########################################################
#                                                       #
#             Installing Required Packages              #
#                                                       #
#########################################################

print_header "Installing Required Packages"

install_hyprland
sleep 2

install_xfce4
sleep 2

install_filetools
sleep 2

install_webtools
sleep 2

install_printers
sleep 2

install_network
sleep 2

install_media
sleep 2

install_terminaltools
sleep 2

install_systemtools
sleep 2

install_system
sleep 2

install_hyprviz
sleep 2

install_sddm_check
sleep 2

install_sddmgrub
sleep 2

install_matuwall
sleep 2

install_awww_wrapper
sleep 2

print_header "Required Packages Installed"

#########################################################
#                                                       #
#                    Install Pywal16                    #
#                                                       #
#########################################################

print_header "Install Pywal16"

if [ -f /usr/bin/wal ]; then
    echo "pywal16 already installed."
else
    yay --noconfirm -S python-pywal16-git
fi

print_header "Pywal16 Installed"

#########################################################
#                                                       #
#                   Install Wallpapers                  #
#                                                       #
#########################################################

print_header "Install Wallpapers"
install_wallpapers
sleep 2
print_header "Wallpapers Installed"

#########################################################
#                                                       #
#                     Install Fonts                     #
#                                                       #
#########################################################

print_header "Install Fonts"
install_fonts
sleep 2
print_header "Fonts Installed"

#########################################################
#                                                       #
#                   Install Icons Root                  #
#                                                       #
#########################################################

print_header "Install Icons (Root)"

echo "-> Installing to root user"
if ! wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh 2>/dev/null; then
    echo "  WARNING: Root icon install failed (network issue?). Continuing."
fi

print_header "Icons Installed"

#########################################################
#                                                       #
#                   Initiating Pywal16                  #
#                                                       #
#########################################################

print_header "Initiating Pywal16"

echo "-> Init pywal16"
wal -i "$SCRIPT_DIR/Wallpapers/default.png"
echo "pywal16 initiated."

echo "-> Copy default wallpaper to .cache"
cp "$SCRIPT_DIR/Wallpapers/default.png" ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force
echo "Default wallpaper copied."

print_header "Pywal16 Initiated"
sleep 2

run_distro_specific_post_wallpaper

#########################################################
#                                                       #
#         Distro-Specific OS Release                    #
#                                                       #
#########################################################

print_header "Configuring OS Release"
run_distro_specific_os_release

#########################################################
#                                                       #
#              Boot Splash & Plymouth                   #
#                                                       #
#########################################################

print_header "Boot Splash Configuration"
run_distro_specific_splash
install_plymouth

#########################################################
#                                                       #
#           Enable Services                             #
#                                                       #
#########################################################

print_header "Enabling Bluetooth"
run_optional sudo systemctl start bluetooth
run_optional sudo systemctl enable bluetooth

print_header "Enabling Cockpit"
run_optional sudo cp "$SCRIPT_DIR/User-Management/manage-users.desktop" /usr/share/applications/
run_optional sudo systemctl enable --now cockpit.socket
run_optional sudo systemctl start cockpit.socket

print_header "Enabling Samba"
if [ -f "$SCRIPT_DIR/smb/smb.conf" ]; then
    run_optional sudo cp "$SCRIPT_DIR/smb/smb.conf" /etc/samba/
fi
run_optional sudo systemctl enable smb nmb
run_optional sudo systemctl start smb nmb
run_optional sudo systemctl restart smb nmb
echo "  Please update the interfaces section of /etc/samba/smb.conf with your IP address"
sleep 3

#########################################################
#                                                       #
#           NVIDIA Information Notice                   #
#                                                       #
#########################################################

print_header "NVIDIA Graphics Card Information"

echo ""
echo "If you installed an NVIDIA Graphics Card, please follow the"
echo "instructions in the nvidia.conf file located at:"
echo "  ~/hyprtk/hypr/conf/nvidia.conf"
echo ""
sleep 5

#########################################################
#                                                       #
#           Confirm Dotfiles Install                    #
#                                                       #
#########################################################

print_header "Confirm Dotfiles Installation"
echo ""
echo "The script will ask for permission to remove existing directories"
echo "and files from ~/.config/ and create symbolic links from"
echo "$SCRIPT_DIR into your ~/.config/ directory."
echo "Answer Yes (Yy) to install, No (Nn) to skip."
echo ""
sleep 5

while true; do
    read -p "DO YOU WANT TO INSTALL THE DOTFILES NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            echo "Dotfiles installation started."
        break;;
        [Nn]* )
            exit;
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done

#########################################################
#                                                       #
#             Check .config Directory                   #
#                                                       #
#########################################################

echo "-> Check if .config folder exists"
if [ -d ~/.config ]; then
    echo ".config folder already exists."
else
    mkdir ~/.config
    echo ".config folder created."
fi
sleep 3

#########################################################
#                                                       #
#           Create Symbolic Links                       #
#                                                       #
#########################################################

print_header "Create Symbolic Links"

run_distro_specific_symlinks

print_subheader "Install General hyprtk Config"

_installSymLink alacritty ~/.config/alacritty "$SCRIPT_DIR/alacritty/" ~/.config
_installSymLink ranger ~/.config/ranger "$SCRIPT_DIR/ranger/" ~/.config
_installSymLink vim ~/.config/vim "$SCRIPT_DIR/vim/" ~/.config
_installSymLink nvim ~/.config/nvim "$SCRIPT_DIR/nvim/" ~/.config
_installSymLink starship ~/.config/starship.toml "$SCRIPT_DIR/starship/starship.toml" ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi "$SCRIPT_DIR/rofi/" ~/.config
_installSymLink dunst ~/.config/dunst "$SCRIPT_DIR/dunst/" ~/.config
_installSymLink wal ~/.config/wal "$SCRIPT_DIR/wal/" ~/.config
_installSymLink btop ~/.config/btop "$SCRIPT_DIR/btop/" ~/.config

#########################################################
#                                                       #
#                  Re-Initiating Pywal16                #
#                                                       #
#########################################################

print_header "Re-Initiating Pywal16"

wal -i "$SCRIPT_DIR/Wallpapers/default.png"
echo "Pywal16 templates initiated!"

print_header "Pywal16 Re-Initiated"

print_subheader "Install GTK hyprtk Config"

_installSymLink gtk-3.0 ~/.config/gtk-3.0 "$SCRIPT_DIR/gtk/gtk-3.0/" ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 "$SCRIPT_DIR/gtk/gtk-4.0/" ~/.config/
_installSymLink themes ~/.local/share/themes "$SCRIPT_DIR/themes" ~/.local/share/
_installSymLink icons ~/.local/share/icons "$SCRIPT_DIR/papirus-icons/icons" ~/.local/share/

print_subheader "Install XFCE hyprtk Config"

_installSymLink xfce4 ~/.config/xfce4 "$SCRIPT_DIR/xfce4" ~/.config/
_installSymLink Thunar ~/.config/Thunar "$SCRIPT_DIR/Thunar" ~/.config/
_installSymLink Mousepad ~/.config/Mousepad "$SCRIPT_DIR/Mousepad" ~/.config/

print_subheader "Install Hyprland hyprtk Config"

_installSymLink hypr ~/.config/hypr "$SCRIPT_DIR/hypr/" ~/.config
_installSymLink fastfetch ~/.config/fastfetch "$SCRIPT_DIR/fastfetch/" ~/.config
_installSymLink waybar ~/.config/waybar "$SCRIPT_DIR/waybar/" ~/.config
_installSymLink swaylock ~/.config/swaylock "$SCRIPT_DIR/swaylock/" ~/.config
_installSymLink swappy ~/.config/swappy "$SCRIPT_DIR/swappy/" ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout "$SCRIPT_DIR/hyprlogout/" ~/.config
_installSymLink waypaper ~/.config/waypaper "$SCRIPT_DIR/waypaper/" ~/.config
_installSymLink zshrc ~/.config/zshrc "$SCRIPT_DIR/zshrc/" ~/.config
_installSymLink ohmyposh ~/.config/ohmyposh "$SCRIPT_DIR/ohmyposh/" ~/.config
_installSymLink matuwall ~/.config/matuwall "$SCRIPT_DIR/matuwall/" ~/.config
_installSymLink wob ~/.config/wob "$SCRIPT_DIR/wob/" ~/.config
mkdir -p ~/.local/bin

run_distro_specific_post_symlinks

#########################################################
#                                                       #
#           Install ZSH and Plugins                     #
#                                                       #
#########################################################

print_header "Install ZSH"

sudo pacman -S zsh --noconfirm

if ! sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null; then
    echo "  WARNING: Oh My Zsh install failed. You can install manually later."
fi

print_subheader "Install ZSH Plugins"

run_optional git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
run_optional git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
run_optional git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting

print_subheader "Update .zshrc"

_installSymLink .zshrc ~/.zshrc "$SCRIPT_DIR/.zshrc" ~/.zshrc

run_optional sudo chsh -s /bin/zsh
run_optional chsh -s /bin/zsh

print_subheader ".zshrc Updated"

_installSymLink standalone ~/.local/bin "$SCRIPT_DIR/standalone/" ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

rm -Rf $HOME/dotfiles

#########################################################
#                                                       #
#           Setup Root User Config                      #
#                                                       #
#########################################################

print_header "Setup Root User Config"

if [ -d "$SCRIPT_DIR/root" ]; then
    if ! sudo cp -r "$SCRIPT_DIR/root" / 2>/dev/null; then
        echo "  WARNING: Failed to copy root config. Continuing."
    else
        echo "  Config and themes copied to ROOT user"
    fi
else
    echo "  WARNING: root/ directory not found. Skipping root config."
fi
sleep 3

run_distro_specific_final

echo "Setup Password Feedback when entering SUDO password"
sleep 3

#########################################################
#                                                       #
#           Congratulations / Complete                  #
#                                                       #
#########################################################

print_header "Installation Complete"

echo ""
echo "  Distribution: $DISTRO_NAME"
echo "  Initramfs: $INITRAMFS_TOOL"
echo "  Install log: $INSTALL_LOG"
echo ""
echo "  NEXT: Update the keyboard layout and screen resolution"
echo "        in ~/hyprtk/hypr/hyprland.conf"
echo ""
echo "  Now proceed with rebooting your system and Enjoy!"
echo ""
