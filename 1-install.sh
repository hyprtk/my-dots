#!/bin/bash
set -e
INSTALL_LOG="/tmp/hyprtk-install.log"
exec 2>"$INSTALL_LOG"
echo "[$(date)] Hyprtk-On-Arch installer started" | tee -a "$INSTALL_LOG"

echo ""
echo " Welcome to Hyprtk-On-Arch — Unified Hyprland & XFCE Installer "
echo " Merged from: arch, archbang, archcraft, archman, bslx,"
echo "              cachyos, endeavouros, garuda, kiro, manjaro, rebornos"
echo ""
echo " You will now be asked to enter your Root password"
echo ""
sleep 2

# ------------------------------------------------------
# Distribution selection
# ------------------------------------------------------
_header "Select your Arch-based distribution"
echo "  1)  Arch Linux"
echo "  2)  ArchBang"
echo "  3)  ArchCraft"
echo "  4)  ArchMan"
echo "  5)  BSLX"
echo "  6)  CachyOS"
echo "  7)  EndeavourOS"
echo "  8)  Garuda"
echo "  9)  Kiro"
echo "  10) Manjaro"
echo "  11) RebornOS"
echo ""
read -p "  Enter your choice [1-11]: " DISTRO_CHOICE

case $DISTRO_CHOICE in
  1) DISTRO="arch" ;;
  2) DISTRO="archbang" ;;
  3) DISTRO="archcraft" ;;
  4) DISTRO="archman" ;;
  5) DISTRO="bslx" ;;
  6) DISTRO="cachy" ;;
  7) DISTRO="endeavour" ;;
  8) DISTRO="garuda" ;;
  9) DISTRO="kiro" ;;
  10) DISTRO="manjaro" ;;
  11) DISTRO="reborn" ;;
  *) echo "  Invalid choice, defaulting to Arch Linux"; DISTRO="arch" ;;
esac
echo ""
echo "[$(date)] Distribution selected: $DISTRO" | tee -a "$INSTALL_LOG"

# ------------------------------------------------------
# Initramfs tool detection
# ------------------------------------------------------
_header "Initramfs Tool Selection"
if command -v dracut &>/dev/null; then
    echo " Detected: dracut"
    DRACUT_AVAIL=1
fi
if command -v mkinitcpio &>/dev/null; then
    echo " Detected: mkinitcpio"
    MKINITCPIO_AVAIL=1
fi

if [ "$DRACUT_AVAIL" = "1" ] && [ "$MKINITCPIO_AVAIL" = "1" ]; then
    echo ""
    echo " Both dracut and mkinitcpio are available."
    echo " 1) Use dracut"
    echo " 2) Use mkinitcpio"
    read -p " Choose initramfs tool [1-2]: " INIT_CHOICE
    case $INIT_CHOICE in
        1) INIT_TOOL="dracut" ;;
        2) INIT_TOOL="mkinitcpio" ;;
        *) echo " Defaulting to mkinitcpio"; INIT_TOOL="mkinitcpio" ;;
    esac
elif [ "$DRACUT_AVAIL" = "1" ]; then
    INIT_TOOL="dracut"
    echo " Only dracut found — using dracut."
else
    INIT_TOOL="mkinitcpio"
    echo " Using mkinitcpio (default or only available)."
fi
echo "[$(date)] Initramfs tool selected: $INIT_TOOL" | tee -a "$INSTALL_LOG"
sleep 2

# ------------------------------------------------------
# Professional header/footer helpers
# ------------------------------------------------------
_header() {
    local title="$1"
    local len="${#title}"
    local total=70
    local pad=$(( (total - len) / 2 ))
    printf '\n  ┌'
    printf '─%.0s' $(seq 1 $total)
    printf '┐\n'
    printf '  │%*s%s%*s│\n' $pad '' "$title" $(( total - len - pad )) ''
    printf '  └'
    printf '─%.0s' $(seq 1 $total)
    printf '┘\n\n'
}

_footer() {
    local msg="$1"
    printf '\n  ──────────────────────────────────────────────────────\n'
    printf '  %s\n' "$msg"
    printf '  ──────────────────────────────────────────────────────\n\n'
}

# ------------------------------------------------------
# Helper: rebuild initramfs
# ------------------------------------------------------
_rebuild_initramfs() {
    local modules="$1"
    echo "[$(date)] Rebuilding initramfs with modules: $modules" | tee -a "$INSTALL_LOG"
    if [ "$INIT_TOOL" = "dracut" ]; then
        if [ -n "$modules" ]; then
            local dracut_conf="/etc/dracut.conf.d/gpu-modules.conf"
            echo "add_drivers+=\" $modules \"" | sudo tee "$dracut_conf" >/dev/null
        fi
        sudo dracut --force --regenerate-all
    else
        if [ -n "$modules" ]; then
            local current_modules
            current_modules=$(grep '^MODULES=' /etc/mkinitcpio.conf | sed 's/MODULES=(//' | sed 's/)//' | sed 's/ //g')
            if [ -n "$current_modules" ]; then
                modules="$current_modules $modules"
            fi
            sudo sed -i "s/^MODULES=()/MODULES=($modules)/" /etc/mkinitcpio.conf
        fi
        sudo mkinitcpio -P
    fi
    echo "[$(date)] Initramfs rebuilt successfully" | tee -a "$INSTALL_LOG"
}

# ------------------------------------------------------
# Helper: install boot splash
# ------------------------------------------------------
_install_splash() {
    echo "[$(date)] Installing boot splash (splash-arch.bmp)" | tee -a "$INSTALL_LOG"
    sudo mkdir -p /usr/share/systemd/bootctl/
    sudo cp ~/hyprtk/distro/arch/splash/splash-arch.bmp /usr/share/systemd/bootctl/splash-arch.bmp 2>/dev/null && \
        echo "splash-arch.bmp copied to /usr/share/systemd/bootctl/" || \
        echo "Warning: splash-arch.bmp not found, skipping"
    if [ "$INIT_TOOL" = "dracut" ]; then
        local dracut_splash="/etc/dracut.conf.d/splash.conf"
        echo "add_drivers+=\" fbcon fbdev vesa \"" | sudo tee "$dracut_splash" >/dev/null
        echo "install_items+=\" /usr/share/systemd/bootctl/splash-arch.bmp \"" | sudo tee -a "$dracut_splash" >/dev/null
        echo "Dracut splash config added"
    else
        if ! grep -q "splash" /etc/mkinitcpio.conf 2>/dev/null; then
            sudo sed -i 's/^HOOKS=([^)]*)/\0 fsck/' /etc/mkinitcpio.conf 2>/dev/null || true
        fi
        echo "mkinitcpio configured for splash support"
    fi
    _rebuild_initramfs ""
    echo "[$(date)] Boot splash installed successfully" | tee -a "$INSTALL_LOG"
}

# ------------------------------------------------------
# Helper: install Plymouth
# ------------------------------------------------------
_install_plymouth() {
    echo "[$(date)] Installing Plymouth and Hyprtk-Plymouth theme" | tee -a "$INSTALL_LOG"
    sudo pacman -S --noconfirm plymouth
    sudo mkdir -p /usr/share/plymouth/themes/Hyprtk-Plymouth
    sudo cp -r ~/hyprtk/Hyprtk-Plymouth/* /usr/share/plymouth/themes/Hyprtk-Plymouth/
    sudo plymouth-set-default-theme -R Hyprtk-Plymouth
    echo "Hyprtk-Plymouth theme installed and set as default"
    if [ "$INIT_TOOL" = "dracut" ]; then
        echo "add_dracutmodules+=\" plymouth \"" | sudo tee /etc/dracut.conf.d/plymouth.conf >/dev/null
        echo "Dracut Plymouth module added"
    else
        if grep -q "^HOOKS=" /etc/mkinitcpio.conf; then
            sudo sed -i 's/^HOOKS=(base udev)/HOOKS=(base udev plymouth)/' /etc/mkinitcpio.conf
            sudo sed -i 's/^HOOKS=(base)/HOOKS=(base plymouth)/' /etc/mkinitcpio.conf
            if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
                sudo sed -i 's/^HOOKS=(/HOOKS=(plymouth /' /etc/mkinitcpio.conf
            fi
        fi
        echo "mkinitcpio Plymouth hook added"
    fi
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& quiet splash/' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' | sudo tee -a /etc/default/grub
    fi
    _rebuild_initramfs ""
    echo "[$(date)] Plymouth installed successfully" | tee -a "$INSTALL_LOG"
}

_header "Hyprtk-On-Arch Installer"
echo "  by hyprtk (Kori Tk) (2026)"
echo "  Merged from: arch, archbang, archcraft, archman, bslx,"
echo "  cachyos, endeavouros, garuda, kiro, manjaro, rebornos"
_footer "Installation starting"
sleep 2

_header "Removing leftover Packages"
sleep 2

# ------------------------------------------------------
# Distro-specific KDE/package removal
# ------------------------------------------------------
case $DISTRO in
    arch|archcraft|archman|cachy|endeavour|garuda|manjaro|reborn)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
        ;;
    archbang)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
        sudo pacman -Rns swaylock --noconfirm 2>/dev/null || true
        ;;
    bslx)
        sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        ;;
    kiro)
        sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
        sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm 2>/dev/null || true
        yay -Rns sddm-git fastfetch-git --noconfirm 2>/dev/null || true
        ;;
esac
echo "[$(date)] Package cleanup complete for $DISTRO" | tee -a "$INSTALL_LOG"

_header "Starting Installation Process"

_header "Loading Installation Libraries"
source $(dirname "$0")/scripts/library.sh
echo ""
sh ~/hyprtk/scripts/set-timezone.sh
_footer "Installation Libraries loaded"
sleep 2

_header "Installing Yay"
echo ""
if sudo pacman -Qs yay > /dev/null ; then
    echo "yay is installed. You can proceed with the installation"
else
    echo "yay is not installed and will be installed now!"
    _installPackagesPacman "base-devel"
    git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git
    cd ~/Downloads/yay-git
    makepkg -si
    cd ~/hyprtk/
    clear
fi
_footer "Yay is installed"
sleep 2

while true; do
    read -p "DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo "Installation started."; break;;
        [Nn]* ) exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

sleep 2
clear
# Source graphics-card.sh so it has access to $INIT_TOOL and library functions
source ~/hyprtk/hypr/packages/graphics-card.sh
sleep 2

clear
while true; do
    read -p "DO YOU WANT TO INSTALL THE CORE APPS NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo "Installation started."; break;;
        [Nn]* ) echo "Installation is Aborted"; exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Installing Core Packages"
echo ""
sh ~/hyprtk/hypr/packages/hyprland.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/xfce4.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/filetools.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/webtools.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/printers.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/network.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/media.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/terminaltools.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/systemtools.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/system.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/hyprviz.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/sddm-check.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/sddmgrub.sh
echo ""; sleep 2
sh ~/hyprtk/hypr/packages/matuwall.sh
echo ""; sleep 2
sh ~/hyprtk/scripts/awww-wrapper.sh
_footer "Core packages installed"

_header "Installing Pywal16"
if [ -f /usr/bin/wal ]; then
    echo "pywal16 already installed."
else
    yay --noconfirm -S python-pywal16-git
fi

_header "Installing Wallpapers"
sh ~/hyprtk/hypr/packages/wallpapers.sh
sleep 2

_header "Installing Fonts"
sh ~/hyprtk/hypr/packages/fonts.sh
sleep 2

_header "Installing Icons (Root)"
echo ""
echo "-> Installing to root user"
wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh

_header "Initiating Pywal16"
echo ""
echo "-> Init pywal16"
wal -i ~/hyprtk/Wallpapers/default.png
echo "pywal16 initiated."
echo ""
echo "-> Copy default wallpaper to .cache"
cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force
echo "default wallpaper copied."

sleep 2
_header "Hyprland Setup"

while true; do
    read -p "DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo "Installation started."; break;;
        [Nn]* ) echo "Installation is Aborted"; exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Generating Xfconf (Thunar)"
echo ""
echo "-> Launching Thunar to populate xfconf"
thunar &
sleep 3
echo "-> Closing Thunar"
killall thunar

_header "Enabling Bluetooth"
sudo systemctl start bluetooth
sudo systemctl enable bluetooth

_header "Enabling Cockpit"
# ------------------------------------------------------
# Distro-specific cockpit/os-release setup
# ------------------------------------------------------
case $DISTRO in
    arch)
        sudo cp ~/hyprtk/distro/arch/os-release/os-release /usr/lib/
        sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
        sudo systemctl enable --now cockpit.socket
        sudo systemctl start cockpit.socket
        ;;
    archbang)
        sudo cp ~/hyprtk/distro/archbang/os-release/os-release /etc/
        sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
        sudo systemctl enable --now cockpit.socket
        sudo systemctl start cockpit.socket
        ;;
    archcraft|archman|bslx|endeavour|garuda|kiro|manjaro|reborn)
        sudo cp ~/hyprtk/distro/$DISTRO/os-release/os-release /usr/lib/
        sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
        sudo systemctl enable --now cockpit.socket
        sudo systemctl start cockpit.socket
        ;;
    cachy)
        sudo cp ~/hyprtk/distro/cachy/os-release/os-release /usr/lib/
        sudo mkdir -p /run/systemd/propagate/.os-release-stage/
        sudo cp ~/hyprtk/distro/cachy/os-release/os-release /run/systemd/propagate/.os-release-stage/
        sudo mkdir -p /run/user/$UID/systemd/propagate/.os-release-stage/
        sudo cp ~/hyprtk/distro/cachy/os-release/os-release /run/user/$UID/systemd/propagate/.os-release-stage/
        if [ -f ~/hyprtk/distro/cachy/cachyos-branding ]; then
            sudo cp ~/hyprtk/distro/cachy/cachyos-branding /usr/share/libalpm/scripts/
            sudo bash /usr/share/libalpm/scripts/cachyos-branding
        fi
        sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
        sudo systemctl enable --now cockpit.socket
        sudo systemctl start cockpit.socket
        ;;
esac
echo "[$(date)] Cockpit setup complete for $DISTRO" | tee -a "$INSTALL_LOG"

# ------------------------------------------------------
# Boot splash installation (for all distributions)
# ------------------------------------------------------
_install_splash

# ------------------------------------------------------
# Plymouth installation (for all distributions)
# ------------------------------------------------------
_install_plymouth

_header "Enabling Samba"
sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
sudo systemctl enable smb nmb
sudo systemctl start smb nmb
sudo systemctl restart smb nmb
echo "Please update the interfaces section of /etc/samba/smb.conf with your IP address"
sleep 3

# ------------------------------------------------------
# Distro-specific wallpaper/GRUB steps
# ------------------------------------------------------
case $DISTRO in
    bslx)
        sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png 2>/dev/null || true
        ;;
    kiro)
        sh ~/hyprtk/scripts/update-grub.sh 2>/dev/null || true
        ;;
esac

_header "NVIDIA Graphics Card Information"
echo ""
echo "If you installed an NVIDIA Graphics Card please follow the instructions in the"
echo "nvidia.conf file located ~/hyprtk/hypr/conf/nvidia.conf"
echo ""
sleep 5

_header "Hyprtk Dotfiles Installation"
echo ""
echo "The script will ask for permission to remove existing directories and files from ~/.config/"
echo "Symbolic links will then be created from ~/hyprtk into your ~/.config/ directory."
echo "But you can decide to keep your personal versions by answering with No (Nn)."
echo ""
sleep 5

_header "Confirm Dotfiles Installation"
while true; do
    read -p " DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo "Installation started."; break;;
        [Nn]* ) exit; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

_header "Checking .config Directory"
echo "-> Check if .config folder exists"
if [ -d ~/.config ]; then
    echo ".config folder already exists."
else
    mkdir ~/.config
    echo ".config folder created."
fi
sleep 3

_header "Creating Symbolic Links"
echo ""
echo "-------------------------------------"
echo "-> Install general hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink alacritty ~/.config/alacritty ~/hyprtk/alacritty/ ~/.config
_installSymLink ranger ~/.config/ranger ~/hyprtk/ranger/ ~/.config
_installSymLink vim ~/.config/vim ~/hyprtk/vim/ ~/.config
_installSymLink nvim ~/.config/nvim ~/hyprtk/nvim/ ~/.config
_installSymLink starship ~/.config/starship.toml ~/hyprtk/starship/starship.toml ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi ~/hyprtk/rofi/ ~/.config
_installSymLink dunst ~/.config/dunst ~/hyprtk/dunst/ ~/.config
_installSymLink wal ~/.config/wal ~/hyprtk/wal/ ~/.config
_installSymLink btop ~/.config/btop ~/hyprtk/btop/ ~/.config

_header "Re-Initiating Pywal16"
echo ""
# ------------------------------------------------------
# Distro-specific pywal re-init
# ------------------------------------------------------
case $DISTRO in
    archcraft)
        wal -i ~/.cache/current-wallpaper.png
        ;;
    *)
        wal -i ~/hyprtk/Wallpapers/default.png
        ;;
esac
echo "Pywal16 templates initiated!"

clear
echo "-------------------------------------"
echo "-> Install GTK hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0/ ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0/ ~/.config/
_installSymLink themes ~/.local/share/themes ~/hyprtk/themes ~/.local/share/
_installSymLink icons ~/.local/share/icons ~/hyprtk/papirus-icons/icons ~/.local/share/

clear
echo "-------------------------------------"
echo "-> Install Xfce hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/xfce4 ~/.config/
_installSymLink Thunar ~/.config/Thunar ~/hyprtk/Thunar ~/.config/
_installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/Mousepad ~/.config/

clear
echo "-------------------------------------"
echo "-> Install Hyprland hyprtk"
echo "-------------------------------------"
echo ""
# ------------------------------------------------------
# Distro-specific hypr mv ordering
# ------------------------------------------------------
case $DISTRO in
    endeavour)
        mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
        _installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/ ~/.config
        ;;
    arch)
        _installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/ ~/.config
        ;;
    *)
        mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
        _installSymLink hypr ~/.config/hypr ~/hyprtk/hypr/ ~/.config
        ;;
esac

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

clear
echo ""
echo "-------------------------------------"
echo "-> Install ZSH"
echo "-------------------------------------"
echo ""
sudo pacman -S zsh --noconfirm
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

echo ""
echo "-------------------------------------"
echo "-> Install ZSH Plugins"
echo "-------------------------------------"
echo ""
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting

_header "Updating .zshrc"
echo ""
echo "-> Install .zshrc"
_installSymLink .zshrc ~/.zshrc ~/hyprtk/.zshrc ~/.zshrc
sudo chsh -s /bin/zsh
chsh -s /bin/zsh

_installSymLink standalone ~/.local/bin ~/hyprtk/standalone/ ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/hyprtk/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh

rm -Rf $HOME/dotfiles

_header "Setup Root User Config"
echo ""
sudo cp -r ~/hyprtk/root /
echo " Copying Config and Themes to ROOT User "
sleep 3

# ------------------------------------------------------
# Distro-specific sudoers formatting
# ------------------------------------------------------
case $DISTRO in
    reborn)
        echo -e '
        Defaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers
        ;;
    *)
        echo -e 'Defaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers
        ;;
esac
echo " Setup Password Feedback when entering SUDO password "
sleep 3

# ------------------------------------------------------
# Copy distro-specific NVIDIA GRUB theme configs
# ------------------------------------------------------
case $DISTRO in
    endeavour|garuda)
        if [ -f ~/hyprtk/distro/$DISTRO/nvidia/grub-nvidia.conf ]; then
            echo "Applying $DISTRO NVIDIA GRUB theme settings..."
            sudo cp ~/hyprtk/distro/$DISTRO/nvidia/grub-nvidia.conf /etc/default/grub-nvidia.conf 2>/dev/null || true
            echo "GRUB theme config saved to /etc/default/grub-nvidia.conf — review before applying"
        fi
        ;;
esac

_header "Installation Complete"
echo "  ✓ All steps finished successfully for $DISTRO"
echo ""
echo "[$(date)] Installation complete for $DISTRO" | tee -a "$INSTALL_LOG"
echo "Install log saved to: $INSTALL_LOG"
_footer "Hyprtk-On-Arch — hyprtk (Kori Tk) (2026)"
echo ""
echo "NEXT: Update the keyboard layout and screen resolution in ~/hyprtk/hypr/hyprland.conf"
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""
