#!/bin/bash
#
#  Hyprtk-On-Arch — Unified Hyprland + XFCE Installer
#  Supports: arch, archbang, archcraft, archman, bslx, cachy,
#            endeavour, garuda, kiro, manjaro, reborn
#
#  by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo " Welcome to the Hyprland & XFCE installer "
echo " I have chosen as my preference to install both, if you choose No on either Environments the installer will fail and close "
echo " I chose it this way so if 1 Environment has problems i still have the other to boot too, enjoy"
echo ""
echo " You will now be asked to enter your Root password to proceed with the installation process"
echo ""
sleep 2
sudo pacman -S figlet --noconfirm
sudo cp "$SCRIPT_DIR/common/figlet/fonts/"* /usr/share/figlet/fonts/
figlet -f 3d "Install"
echo "

by hyprtk (Kori Tk) (2026)
#########################################################
"
sleep 2
echo ""
clear
echo "
#########################################################
#                                                       #
#             Removing leftover Packages                #
#                                                       #
#########################################################
"
sleep 2
sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm 2>/dev/null || true
sudo pacman -Rns plasma kde-applications --noconfirm 2>/dev/null || true
echo ""
clear
echo "
#########################################################
#                                                       #
#             Starting Installation Process             #
#                                                       #
#########################################################
"
sleep 2
echo ""
clear
echo "
#########################################################
#                                                       #
#              Load Installation Libraries              #
#                                                       #
#########################################################
"
echo ""
source "$SCRIPT_DIR/scripts/library.sh"
echo ""
echo ""
bash "$SCRIPT_DIR/scripts/set-timezone.sh"
echo ""
sleep 2
clear
echo "
#########################################################
#                                                       #
#            Installation Libraries loaded              #
#                                                       #
#########################################################
"
echo ""
sleep 2
clear
echo "
#########################################################
#                                                       #
#                  Detect Distribution                  #
#                                                       #
#########################################################
"

# Distro detection
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_ID_LIKE="$ID_LIKE"
    else
        DISTRO_ID="unknown"
        DISTRO_ID_LIKE=""
    fi
    
    case "$DISTRO_ID" in
        arch|archarm)
            DISTRO_NAME="arch"
            ;;
        archbang)
            DISTRO_NAME="archbang"
            ;;
        archcraft)
            DISTRO_NAME="archcraft"
            ;;
        archman)
            DISTRO_NAME="archman"
            ;;
        blackarch|blankon|baselinux)
            DISTRO_NAME="bslx"
            ;;
        cachyos)
            DISTRO_NAME="cachy"
            ;;
        endeavouros)
            DISTRO_NAME="endeavour"
            ;;
        garuda)
            DISTRO_NAME="garuda"
            ;;
        kiro)
            DISTRO_NAME="kiro"
            ;;
        manjaro)
            DISTRO_NAME="manjaro"
            ;;
        rebornos)
            DISTRO_NAME="reborn"
            ;;
        *)
            # Fallback to ID_LIKE
            case "$DISTRO_ID_LIKE" in
                *arch*) DISTRO_NAME="arch" ;;
                *) DISTRO_NAME="arch" ;;
            esac
            ;;
    esac
    
    echo "Detected distribution: $DISTRO_NAME"
}

detect_initramfs() {
    if command -v dracut &>/dev/null; then
        INITRAMFS_TOOL="dracut"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS_TOOL="mkinitcpio"
    else
        INITRAMFS_TOOL="unknown"
    fi
    echo "Initramfs tool detected: $INITRAMFS_TOOL"
}

detect_distro
detect_initramfs
echo ""
sleep 2
clear

echo "
#########################################################
#                                                       #
#                     Install Yay                       #
#                                                       #
#########################################################
"
echo ""
if sudo pacman -Qs yay > /dev/null ; then
    echo "yay is installed. You can proceed with the installation"
else
    echo "yay is not installed and will be installed now!"
    _installPackagesPacman "base-devel"
    git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git
    cd ~/Downloads/yay-git
    makepkg -si --noconfirm
    cd "$SCRIPT_DIR"
    clear
fi
echo ""
clear
echo "
#########################################################
#                                                       #
#                    Yay is Installed                   #
#                                                       #
#########################################################
"
sleep 2
echo ""
echo ""
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
echo ""
echo ""
sleep 2
echo ""
clear
bash "$SCRIPT_DIR/hypr/packages/graphics-card.sh"
sleep 2
clear
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
echo ""
figlet -f 3d "Core Apps"
echo ""
echo "
#########################################################
#                                                       #
#             Installing required Packages              #
#                                                       #
#########################################################
"

echo ""
bash "$SCRIPT_DIR/hypr/packages/hyprland.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/xfce4.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/filetools.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/webtools.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/printers.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/network.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/media.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/terminaltools.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/systemtools.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/system.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/hyprviz.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/sddm-check.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/sddmgrub.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/hypr/packages/matuwall.sh"
echo ""
sleep 2
echo ""
bash "$SCRIPT_DIR/scripts/awww-wrapper.sh"
echo ""
echo "
#########################################################
#                                                       #
#              Installed required Packages              #
#                                                       #
#########################################################
"
echo ""
clear
echo "
#########################################################
#                                                       #
#                    Install Pywal16                    #
#                                                       #
#########################################################
"
if [ -f /usr/bin/wal ]; then
    echo "pywal16 already installed."
else
    yay --noconfirm -S python-pywal16-git
fi
echo ""
echo "
#########################################################
#                                                       #
#                    Pywal16 Installed                  #
#                                                       #
#########################################################
"
echo ""
clear
echo ""
echo "
#########################################################
#                                                       #
#                   Install Wallpapers                  #
#                                                       #
#########################################################
"
echo ""
echo ""
bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh"
echo ""
sleep 2
echo "
#########################################################
#                                                       #
#                 Wallpapers Installed                  #
#                                                       #
#########################################################
"
echo ""
clear
echo "
#########################################################
#                                                       #
#                     Install Fonts                     #
#                                                       #
#########################################################
"
echo ""
echo ""
bash "$SCRIPT_DIR/hypr/packages/fonts.sh"
echo ""
sleep 2
echo "
#########################################################
#                                                       #
#                    Fonts Installed                    #
#                                                       #
#########################################################
"
echo ""
clear
echo ""
echo "
#########################################################
#                                                       #
#                   Install Icons Root                  #
#                                                       #
#########################################################
"
echo ""
echo "-> Installing to root user"
wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh

echo "
#########################################################
#                                                       #
#                    Icons Installed                    #
#                                                       #
#########################################################
"
echo ""
clear
echo ""
echo "
#########################################################
#                                                       #
#                   Initiating Pywal16                  #
#                                                       #
#########################################################
"
echo ""
echo "-> Init pywal16"
wal -i "$SCRIPT_DIR/common/Wallpapers/default.png"
echo "pywal16 initiated."
echo ""
echo ""
echo "-> Copy default wallpaper to .cache"
cp "$SCRIPT_DIR/common/Wallpapers/default.png" ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
xdg-user-dirs-update --force
xdg-user-dirs-gtk-update --force
echo "default wallpaper copied."
echo ""
echo "
#########################################################
#                                                       #
#                    Pywal16 Initiated                  #
#                                                       #
#########################################################
"
echo ""
sleep 2
clear
echo ""
figlet -f 3d "Hyprland"
echo ""
echo " by hyprtk (Kori Tk) (2026) "
echo " ------------------------------------------------------------------- "
echo ""
echo ""
while true; do
    read -p "DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
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
echo ""
echo ""
echo "
#########################################################
#                                                       #
#            Launch Thunar to generate xfconf           #
#                                                       #
#########################################################
"
echo ""
echo "-> Launching Thunar to populate xfconf"
thunar &
sleep 3
echo ""
echo ""
echo "-> Closing Thunar"
killall thunar
echo ""
clear
echo "
#########################################################
#                                                       #
#                   Enabling Bluetooth                  #
#                                                       #
#########################################################
"
sudo systemctl start bluetooth
sudo systemctl enable bluetooth
echo ""
echo ""
clear
echo "
#########################################################
#                                                       #
#               Distribution-Specific Setup             #
#                                                       #
#########################################################
"

# ---- Distro-specific: Cockpit / OS-Release / Splash / Initramfs ----
case "$DISTRO_NAME" in
    arch)
        echo "-> Arch Linux setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    cachy)
        echo "-> CachyOS setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/systemd/propagate/.os-release-stage/
        sudo cp "$SCRIPT_DIR/distro/os-release/cachy" /run/user/$UID/systemd/propagate/.os-release-stage/
        sudo cp "$SCRIPT_DIR/distro/os-release/cachyos-branding" /usr/share/libalpm/scripts/
        sudo bash /usr/share/libalpm/scripts/cachyos-branding
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    endeavour)
        echo "-> EndeavourOS setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/endeavour" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    garuda)
        echo "-> Garuda Linux setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/garuda" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    kiro)
        echo "-> Kiro Linux setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/kiro" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    manjaro)
        echo "-> Manjaro setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/manjaro" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    reborn)
        echo "-> RebornOS setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/reborn" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    archbang)
        sudo cp "$SCRIPT_DIR/distro/os-release/archbang" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    archcraft)
        sudo cp "$SCRIPT_DIR/distro/os-release/archcraft" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    archman)
        sudo cp "$SCRIPT_DIR/distro/os-release/archman" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    bslx)
        sudo cp "$SCRIPT_DIR/distro/os-release/bslx" /usr/lib/os-release
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
    *)
        echo "-> Generic Arch setup"
        sudo cp "$SCRIPT_DIR/distro/os-release/arch" /usr/lib/os-release 2>/dev/null || true
        sudo cp "$SCRIPT_DIR/common/User-Management/manage-users.desktop" /usr/share/applications/
        sudo systemctl enable --now cockpit.socket 2>/dev/null || true
        sudo systemctl start cockpit.socket 2>/dev/null || true
        ;;
esac

# ---- Initramfs rebuild ----
echo ""
echo "-> Rebuilding initramfs with $INITRAMFS_TOOL"
case "$INITRAMFS_TOOL" in
    mkinitcpio)
        sudo mkinitcpio -P
        ;;
    dracut)
        sudo dracut --force --regenerate-all
        ;;
    *)
        echo "Warning: Unknown initramfs tool. Skipping rebuild."
        ;;
esac

echo ""
echo ""
clear
echo "
#########################################################
#                                                       #
#                   Enabling Samba                      #
#                                                       #
#########################################################
"
sudo cp "$SCRIPT_DIR/common/smb/smb.conf" /etc/samba/
sudo systemctl enable smb nmb
sudo systemctl start smb nmb
sudo systemctl restart smb nmb
echo "Please update the interfaces section of /etc/samba/smb.conf with your IP address"
sleep 3
clear
echo "
#########################################################
#                                                       #
#           IMPORTANT Graphic Card Information          #
#                                                       #
#########################################################
"
echo ""
echo ""
echo "If you installed an NVIDIA Graphics Card please follow the instructions in the"
echo "nvidia.conf file located ~/hyprtk/hypr/conf/nvidia.conf"
echo ""
sleep 5
clear
figlet -f 3d "hyprtk"
echo ""
echo " by hyprtk (Kori Tk) (2026) "
echo " ------------------------------------------------------------------- "
echo ""
echo "The script will ask for permission to remove existing directories and files from ~/.config/"
echo "Symbolic links will then be created from ~/hyprtk into your ~/.config/ directory."
echo "But you can decide to keep your personal versions by answering with No (Nn)."
echo ""
sleep 5
clear
echo ""
echo "
#########################################################
#                                                       #
#              Confirm dotfile files Install            #
#                                                       #
#########################################################
"
while true; do
    read -p " DO YOU WANT TO START THE INSTALLATION NOW? (Yy/Nn): " yn
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
echo ""
clear
echo "
#########################################################
#                                                       #
#             Check .config directory exists            #
#                                                       #
#########################################################
"
echo ""
echo "-> Check if .config folder exists"

if [ -d ~/.config ]; then
    echo ".config folder already exists."
else
    mkdir ~/.config
    echo ".config folder created."
fi
echo ""
sleep 3
clear
echo "
#########################################################
#                                                       #
#                 Create Symbolic Links                 #
#                                                       #
#########################################################
"
echo ""
echo ""
echo "-------------------------------------"
echo "-> Install general hyprtk"
echo "-------------------------------------"
echo ""
echo ""
_installSymLink alacritty ~/.config/alacritty "$SCRIPT_DIR/common/alacritty/" ~/.config
_installSymLink ranger ~/.config/ranger "$SCRIPT_DIR/common/ranger/" ~/.config
_installSymLink vim ~/.config/vim "$SCRIPT_DIR/common/vim/" ~/.config
_installSymLink nvim ~/.config/nvim "$SCRIPT_DIR/common/nvim/" ~/.config
_installSymLink starship ~/.config/starship.toml "$SCRIPT_DIR/common/starship/starship.toml" ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi "$SCRIPT_DIR/common/rofi/" ~/.config
_installSymLink dunst ~/.config/dunst "$SCRIPT_DIR/common/dunst/" ~/.config
_installSymLink wal ~/.config/wal "$SCRIPT_DIR/common/wal/" ~/.config
_installSymLink btop ~/.config/btop "$SCRIPT_DIR/common/btop/" ~/.config
echo ""
clear
echo "
#########################################################
#                                                       #
#                  Re-Initiating Pywal16                #
#                                                       #
#########################################################
"
echo ""
wal -i "$SCRIPT_DIR/common/Wallpapers/default.png"
echo "Pywal16 templates initiated!"
echo ""
echo ""
echo "
#########################################################
#                                                       #
#                    Pywal16 Initiated                  #
#                                                       #
#########################################################
"
echo ""
clear
echo "-------------------------------------"
echo "-> Install GTK hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink gtk-3.0 ~/.config/gtk-3.0 "$SCRIPT_DIR/common/gtk/gtk-3.0/" ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 "$SCRIPT_DIR/common/gtk/gtk-4.0/" ~/.config/
_installSymLink themes ~/.local/share/themes "$SCRIPT_DIR/common/themes" ~/.local/share/
_installSymLink icons ~/.local/share/icons "$SCRIPT_DIR/common/papirus-icons/icons" ~/.local/share/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Xfce hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink xfce4 ~/.config/xfce4 "$SCRIPT_DIR/common/xfce4" ~/.config/
_installSymLink Thunar ~/.config/Thunar "$SCRIPT_DIR/common/Thunar" ~/.config/
_installSymLink Mousepad ~/.config/Mousepad "$SCRIPT_DIR/common/Mousepad" ~/.config/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Hyprland hyprtk"
echo "-------------------------------------"
echo ""
mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true
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
echo ""
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Install ZSH"
echo "-------------------------------------"
echo ""
sudo pacman -S zsh --noconfirm
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
echo ""
echo ""
echo "-------------------------------------"
echo "-> Install ZSH Plugins"
echo "-------------------------------------"
echo ""
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null || true
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting 2>/dev/null || true
echo ""
echo "
#########################################################
#                                                       #
#                      Update .zshrc                    #
#                                                       #
#########################################################
"
echo ""
echo "-> Install .zshrc"
echo ""
_installSymLink .zshrc ~/.zshrc "$SCRIPT_DIR/common/.zshrc" ~/.zshrc
echo ""
sudo chsh -s /bin/zsh
chsh -s /bin/zsh
echo "
#########################################################
#                                                       #
#                    .zshrc Updated                     #
#                                                       #
#########################################################
"
echo ""
_installSymLink standalone ~/.local/bin "$SCRIPT_DIR/common/standalone/" ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$SCRIPT_DIR/common/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh
echo ""
echo ""
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Setup Root User Config"
echo "-------------------------------------"
echo ""
sudo cp -r "$SCRIPT_DIR/distro/root/"* /
echo " Copying Config and Themes to ROOT User "
echo ""
sleep 3
echo -e 'Defaults env_reset,pwfeedback' | sudo tee -a /etc/sudoers
echo " Setup Password Feedback when entering SUDO password "
echo ""
sleep 3
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Create ~/hyprtk symlink for runtime"
echo "-------------------------------------"
echo ""
if [ ! -L ~/hyprtk ] && [ ! -d ~/hyprtk ]; then
    ln -sf "$SCRIPT_DIR" ~/hyprtk
    echo "Symlink ~/hyprtk -> $SCRIPT_DIR created."
elif [ -L ~/hyprtk ]; then
    echo "Symlink ~/hyprtk already exists."
fi
echo ""
sleep 2
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Congratulations Setup Complete"
echo "-------------------------------------"
echo ""
echo "DONE!"
echo ""
echo "NEXT: Update the keyboard layout and screen resolution in $SCRIPT_DIR/hypr/hyprland.conf"
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""
