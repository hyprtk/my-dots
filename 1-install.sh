#!/bin/bash

DISTRO=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi

CWD="$(dirname "$0")"

_header() {
    clear
    echo "=============================================================================="
    printf "  %-76s\n" "$1"
    echo "=============================================================================="
    echo ""
}

_footer() {
    echo ""
    echo "------------------------------------------------------------------------------"
    printf "  \342\234\223 %-74s\n" "$1 completed"
    echo "------------------------------------------------------------------------------"
    sleep 2
}

_regenerate_initramfs() {
    if command -v dracut &>/dev/null; then
        sudo dracut --force
    else
        sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
    fi
}

_regenerate_all_initramfs() {
    if command -v dracut &>/dev/null; then
        sudo dracut --regenerate-all --force
    else
        sudo mkinitcpio -P
    fi
}

_header "Hyprland & XFCE Installation - Detected: ${DISTRO:-unknown}"
echo ""
echo "  Root password will be required to proceed."
echo ""
sleep 2

_header "Removing leftover packages"
sleep 1

case $DISTRO in
    bslx)
        sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rcs plasma kde-applications --noconfirm
        ;;
    kiro)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rns plasma kde-applications --noconfirm
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm
        yay -Rns sddm-git fastfetch-git --noconfirm
        ;;
    archbang)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rns plasma kde-applications --noconfirm
        sudo pacman -Rns swaylock --noconfirm
        ;;
    *)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
        sudo pacman -Rns plasma kde-applications --noconfirm
        ;;
esac

_footer "Removing leftover packages"

_header "Loading installation libraries"
source "$CWD/scripts/library.sh"
sh ~/hyprtk/scripts/set-timezone.sh
_footer "Loading installation libraries"

_header "Installing Yay (AUR helper)"
if sudo pacman -Qs yay > /dev/null ; then
    echo "  yay is already installed."
else
    echo "  yay is not installed. Installing now..."
    _installPackagesPacman "base-devel"
    git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git
    cd ~/Downloads/yay-git
    makepkg -si
    cd ~/hyprtk/
fi
_footer "Installing Yay"

while true; do
    read -p "  Proceed with the full installation? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo ""; break;;
        [Nn]* ) exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Graphics Card Setup"
echo ""
echo "  1) Intel"
echo "  2) AMD"
echo "  3) Nvidia"
echo "  4) Virtualization (QEMU/virt & VMware)"
echo ""
read GRAPHICSCARD
case $GRAPHICSCARD in
1)
  sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel vulkan-intel;;
2)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  _regenerate_initramfs;;
3)
  sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
  echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
  sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva && yay --noconfirm -S libva-nvidia-driver-git
  _regenerate_initramfs;;
4)
  _installPackagesPacman qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
  _installPackagesYay xf86-video-vmware
  sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
  sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
  sudo systemctl enable --now vmtoolsd 2>/dev/null || true;;
*)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  _regenerate_initramfs;;
esac
_footer "Graphics Card Setup"

while true; do
    read -p "  Install core applications? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo ""; break;;
        [Nn]* ) echo "Installation aborted."; exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Installing core packages"

_header "  -> Hyprland"
sudo pacman -S hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost nwg-look mission-center curl imagemagick jq bc brightnessctl playerctl libadwaita gtk-layer-shell python python-pip python-virtualenv python-gobject gtk4 wob --noconfirm
yay -S awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb 7zip unzip unrar waybar-git --noconfirm
_footer "Hyprland"

_header "  -> XFCE4"
sudo pacman -S xfce4 xfce4-goodies parole --noconfirm
yay -S tumbler-extra-thumbnailers --noconfirm
_footer "XFCE4"

_header "  -> File Tools"
sudo pacman -S thunar mousepad --noconfirm
yay -S thunar-shares-plugin --noconfirm
_footer "File Tools"

_header "  -> Web Tools"
sudo pacman -S chromium --noconfirm
yay -S brave-bin github-desktop-bin --noconfirm
_footer "Web Tools"

_header "  -> Printer"
yay -S cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed libusb ipp-usb xdg-utils colord logrotate --noconfirm
_footer "Printer"

_header "  -> Network"
sudo pacman -S networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb gvfs-wsdd ntfs-3g samba --noconfirm
_footer "Network"

_header "  -> Media"
sudo pacman -S xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg --noconfirm
yay -S hyprquickframe-git --noconfirm
_footer "Media"

_header "  -> Terminal Tools"
sudo pacman -S eza micro xfce4-terminal btop alacritty kitty starship ranger nano figlet neovim --noconfirm
yay -S fastfetch --noconfirm
_footer "Terminal Tools"

_header "  -> System Tools"
sudo pacman -S timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit --noconfirm
yay -S gnome-disk-utility --noconfirm
_footer "System Tools"

_header "  -> System Packages"
sudo pacman -S sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd exa python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp pcp-gui gtk4-layer-shell hyprpicker --noconfirm
sudo pacman -S $(pacman -Ssq 'pcp-pmda-*') --noconfirm
if [ "$DISTRO" = "reborn" ]; then
    yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek tumbler-extra-thumbnailers --noconfirm
else
    yay -S bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers --noconfirm
fi
echo ""
echo "  Installing Papirus folder icons..."
wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
_footer "System Packages"

_header "  -> HyprViz (Hyprland config tool)"
cd $HOME/Downloads/yay-git/src/
git clone https://aur.archlinux.org/hyprviz-bin.git
cd hyprviz-bin
makepkg -si
_footer "HyprViz"

_header "  -> SDDM Configuration"
sh ~/hyprtk/scripts/rm-dm-managers.sh
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
fi
sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
echo "  SDDM configured."
_footer "SDDM Configuration"

_header "  -> SDDM & GRUB Theming"
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
fi
sudo rm -rf /usr/share/grub/themes/*
sudo rm -rf /boot/grub/themes/*
sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
cp ~/hyprtk/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/
sudo cp ~/hyprtk/sddm/theme.conf /usr/share/sddm/themes/Sugar-Candy/
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"'| sudo tee -a /etc/default/grub
echo -e 'GRUB_COLOR_NORMAL="white/black"'| sudo tee -a /etc/default/grub
echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"'| sudo tee -a /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo "  SDDM and GRUB themed with current wallpaper."
_footer "SDDM & GRUB Theming"

_header "  -> Matuwall (Wallpaper picker)"
git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall
cd ~/.local/share/Matuwall
/usr/bin/python -m venv --system-site-packages .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
mkdir -p ~/.local/bin
ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
cd -
_footer "Matuwall"

_header "  -> AWWW Wallpaper utility"
sh ~/hyprtk/scripts/awww-wrapper.sh
_footer "AWWW Wallpaper utility"

case $DISTRO in
    kiro)
        _header "  -> GRUB Updater (Kiro-specific)"
        sh ~/hyprtk/scripts/grudupdater.sh
        _footer "GRUB Updater"
        ;;
esac

_footer "Core packages installation"

_header "Installing Pywal16"
if [ -f /usr/bin/wal ]; then
    echo "  pywal16 already installed."
else
    yay --noconfirm -S python-pywal16-git
fi
_footer "Installing Pywal16"

_header "Installing Wallpapers"
echo ""
echo "  Select wallpaper source:"
while true; do
    read -p "  Clone wallpaper repository? If not, 3 default wallpapers will be used. (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ -d ~/Pictures/Wallpapers/ ]; then
                echo "  Wallpaper folder already exists."
            else
                git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
                echo "  Wallpapers cloned from repository."
            fi
        break;;
        [Nn]* )
            if [ -d ~/Pictures/Wallpapers/ ]; then
                echo "  Wallpapers folder already exists."
            else
                mkdir ~/Pictures/Wallpapers
            fi
            cp ~/hyprtk/Wallpapers/* ~/Pictures/Wallpapers
            echo "  Default wallpapers installed."
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done
_footer "Installing Wallpapers"

_header "Installing Fonts"
echo ""
while true; do
    read -p "  Clone font repository? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            if [ -d ~/.local/share/fonts/ ]; then
                echo "  Fonts folder already exists."
            else
                git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
                echo "  User fonts cloned from repository."
            fi
        break;;
        [Nn]* )
            if [ -d ~/.local/share/fonts/ ]; then
                echo "  Fonts folder already exists."
            else
                mkdir ~/.local/share/fonts
            fi
            sudo cp -r ~/hyprtk/fonts/* /usr/share/fonts
            sudo cp -r ~/.local/share/fonts/* /usr/share/fonts
            echo "  System fonts installed."
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done
_footer "Installing Fonts"

_header "Installing Root Icons"
echo ""
echo "  Installing Papirus icon theme for root user..."
wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh
_footer "Installing Root Icons"

_header "Initializing Pywal16"
wal -i ~/hyprtk/Wallpapers/default.png
echo "  Pywal16 initialized."
echo ""
echo "  Copying default wallpaper..."
cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png

case $DISTRO in
    bslx)
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
        ;;
esac

xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force
echo "  Default wallpaper copied to system cache."
_footer "Initializing Pywal16"

_header "Configuring system services"

while true; do
    read -p "  Apply dotfiles configuration? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo ""; break;;
        [Nn]* ) echo "Installation aborted."; exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

echo "  Generating xfconf via Thunar..."
thunar & sleep 3
killall thunar
echo "  Xfconf populated."

echo ""
echo "  Enabling Bluetooth..."
sudo systemctl start bluetooth
sudo systemctl enable bluetooth

echo ""
echo "  Configuring Cockpit..."
case $DISTRO in
    cachy)
        sudo cp "$CWD/os-release/distros/cachy" /usr/lib/os-release
        sudo cp "$CWD/os-release/distros/cachy" /run/systemd/propagate/.os-release-stage/
        sudo cp "$CWD/os-release/distros/cachy" "/run/user/$UID/systemd/propagate/.os-release-stage/"
        sudo cp "$CWD/os-release/distros/cachyos-branding" /usr/share/libalpm/scripts/
        sudo bash /usr/share/libalpm/scripts/cachyos-branding
        ;;
    arch|archcraft)
        sudo cp "$CWD/os-release/distros/$DISTRO" /usr/lib/os-release
        sudo cp "$CWD/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        _regenerate_all_initramfs
        ;;
    archbang)
        sudo cp "$CWD/os-release/distros/archbang" /etc/os-release
        ;;
    *)
        if [ -f "$CWD/os-release/distros/$DISTRO" ]; then
            sudo cp "$CWD/os-release/distros/$DISTRO" /usr/lib/os-release
        else
            sudo cp "$CWD/os-release/os-release" /usr/lib/os-release
        fi
        ;;
esac
sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
sudo systemctl enable --now cockpit.socket
sudo systemctl start cockpit.socket

echo ""
echo "  Enabling Samba..."
sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
sudo systemctl enable smb nmb
sudo systemctl start smb nmb
sudo systemctl restart smb nmb
echo "  Update the interfaces section of /etc/samba/smb.conf with your IP address."

sleep 3

echo ""
echo "  ------------------------------------------------------------------------------"
echo "  Note: If you use an NVIDIA graphics card, configure nvidia.conf at"
echo "        ~/hyprtk/hypr/conf/nvidia.conf"
echo "  ------------------------------------------------------------------------------"
sleep 3

_header "Hyprland dotfiles setup"
echo ""
echo "  The installer will ask for permission to replace existing ~/.config/ files."
echo "  Symbolic links will be created from the merged dots directory."
echo "  Answer No to keep your current configuration files."
echo ""
sleep 3

while true; do
    read -p "  Apply Hyprland dotfiles now? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo ""; break;;
        [Nn]* ) exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Checking ~/.config directory"
if [ -d ~/.config ]; then
    echo "  ~/.config already exists."
else
    mkdir ~/.config
    echo "  ~/.config created."
fi
sleep 2

_header "Creating symbolic links"

case $DISTRO in
    endeavour)
        mv ~/.config/hypr ~/.config/hypr-old
        ;;
esac

_installSymLink alacritty ~/.config/alacritty "$CWD/alacritty/" ~/.config
_installSymLink ranger ~/.config/ranger "$CWD/ranger/" ~/.config
_installSymLink vim ~/.config/vim "$CWD/vim/" ~/.config
_installSymLink nvim ~/.config/nvim "$CWD/nvim/" ~/.config
_installSymLink starship ~/.config/starship.toml "$CWD/starship/starship.toml" ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi "$CWD/rofi/" ~/.config
_installSymLink dunst ~/.config/dunst "$CWD/dunst/" ~/.config
_installSymLink wal ~/.config/wal "$CWD/wal/" ~/.config
_installSymLink btop ~/.config/btop "$CWD/btop/" ~/.config

_header "Re-initializing Pywal16"
case $DISTRO in
    archcraft)
        wal -i ~/.cache/current-wallpaper.png
        ;;
    *)
        wal -i "$CWD/Wallpapers/default.png"
        ;;
esac
_footer "Pywal16 re-initialization"

_header "Linking GTK configuration"
_installSymLink gtk-3.0 ~/.config/gtk-3.0 "$CWD/gtk/gtk-3.0/" ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 "$CWD/gtk/gtk-4.0/" ~/.config/
_installSymLink themes ~/.local/share/themes "$CWD/themes" ~/.local/share/
_installSymLink icons ~/.local/share/icons "$CWD/papirus-icons/icons" ~/.local/share/

_header "Linking XFCE configuration"
_installSymLink xfce4 ~/.config/xfce4 "$CWD/xfce4" ~/.config/
_installSymLink Thunar ~/.config/Thunar "$CWD/Thunar" ~/.config/
_installSymLink Mousepad ~/.config/Mousepad "$CWD/Mousepad" ~/.config/

_header "Linking Hyprland configuration"

case $DISTRO in
    arch|archbang|endeavour)
        ;;
    *)
        mv ~/.config/hypr ~/.config/hypr-old
        ;;
esac

_installSymLink hypr ~/.config/hypr "$CWD/hypr/" ~/.config
_installSymLink fastfetch ~/.config/fastfetch "$CWD/fastfetch/" ~/.config
_installSymLink waybar ~/.config/waybar "$CWD/waybar/" ~/.config
_installSymLink swaylock ~/.config/swaylock "$CWD/swaylock/" ~/.config
_installSymLink swappy ~/.config/swappy "$CWD/swappy/" ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout "$CWD/hyprlogout/" ~/.config
_installSymLink waypaper ~/.config/waypaper "$CWD/waypaper/" ~/.config
_installSymLink zshrc ~/.config/zshrc "$CWD/zshrc/" ~/.config
_installSymLink ohmyposh ~/.config/ohmyposh "$CWD/ohmyposh/" ~/.config
_installSymLink matuwall ~/.config/matuwall "$CWD/matuwall/" ~/.config
_installSymLink wob ~/.config/wob "$CWD/wob/" ~/.config
mkdir -p ~/.local/bin

_header "Installing ZSH"
sudo pacman -S zsh --noconfirm
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

_header "Installing ZSH plugins"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting

_header "Configuring .zshrc"
_installSymLink .zshrc ~/.zshrc "$CWD/.zshrc" ~/.zshrc
sudo chsh -s /bin/zsh
chsh -s /bin/zsh
_footer ".zshrc configuration"

_header "Linking standalone utilities"
_installSymLink standalone ~/.local/bin "$CWD/standalone/" ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$CWD/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh

rm -Rf "$HOME/dotfiles"

_header "Setting up root user configuration"
sudo cp -r "$CWD/root" /
echo "  Root user configuration applied."
sleep 3
echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers
echo "  Sudo password feedback enabled."
sleep 3

_header "Installation complete"
echo ""
echo "  DONE!"
echo ""
echo "  Next steps:"
echo "    - Update keyboard layout in ~/hyprtk/hypr/hyprland.conf"
echo "    - Update screen resolution in ~/hyprtk/hypr/hyprland.conf"
echo "    - Reboot your system"
echo ""
echo "=============================================================================="
