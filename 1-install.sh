#!/bin/bash

echo ""
echo " Welcome to the Hyprland & XFCE installer "
echo " I have chosen as my preference to install both, if you choose No on either Environments the installer will fail and close "
echo " I chose it this way so if 1 Enviroment has problems i still have the other to boot too, enjoy"
echo""
echo " You will now be asked to enter your Root password to proceed with the installation process"
echo""
sleep 2

# ------------------------------------------------------
# Detect distro and set configuration
# ------------------------------------------------------
_detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    elif [ -f /usr/lib/os-release ]; then
        . /usr/lib/os-release
    fi
    DISTRO_ID="${ID:-arch}"

    case "$DISTRO_ID" in
        arch)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=true
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="none"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        archbang)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/etc/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="swaylock"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        archcraft)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=true
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/.cache/current-wallpaper.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        archman)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        bslx)
            KDE_REMOVE_FLAG="-Rcs"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=true
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        cachyos)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=true
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        endeavouros)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=true
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="symlinks-before"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        garuda)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=true
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        kiro)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="kiro-xfce"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="grudupdater"
            SUDOERS_FORMAT="standard"
            ;;
        manjaro)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
        reborn)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="reborn"
            ;;
        *)
            KDE_REMOVE_FLAG="-Rns"
            OS_RELEASE_PATH="/usr/lib/"
            HAS_SPLASH=false
            HAS_CACHYOS_BRANDING=false
            EXTRA_REMOVALS="none"
            HYPR_BACKUP_POSITION="hypr-section"
            PYWAL_IMAGE="~/hyprtk/Wallpapers/default.png"
            HAS_BOOT_GRUB_COPY=false
            HAS_EXTRA_SCRIPTS="none"
            SUDOERS_FORMAT="standard"
            ;;
    esac
}

_detect_distro

sudo pacman -S figlet --noconfirm
sudo cp ~/hyprtk/figlet/fonts/* /usr/share/figlet/fonts/
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
sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
sudo pacman "$KDE_REMOVE_FLAG" plasma kde-applications --noconfirm

case "$EXTRA_REMOVALS" in
    swaylock)
        sudo pacman -Rns swaylock --noconfirm
        ;;
    kiro-xfce)
        sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm
        yay -Rns sddm-git fastfetch-git --noconfirm
        sleep 5
        ;;
esac

echo""
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
source $(dirname "$0")/scripts/library.sh
echo ""
echo ""
sh ~/hyprtk/scripts/set-timezone.sh
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
    makepkg -si
    cd ~/hyprtk/
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
sh ~/hyprtk/hypr/packages/graphics-card.sh
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
sh ~/hyprtk/hypr/packages/hyprland.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/xfce4.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/filetools.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/webtools.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/printers.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/network.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/media.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/terminaltools.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/systemtools.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/system.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/hyprviz.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/sddm-check.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/sddmgrub.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/hypr/packages/matuwall.sh
echo ""
sleep 2
echo ""
sh ~/hyprtk/scripts/awww-wrapper.sh
echo ""

case "$HAS_EXTRA_SCRIPTS" in
    grudupdater)
        sh ~/hyprtk/scripts/grudupdater.sh
        echo ""
        ;;
esac

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
sh ~/hyprtk/hypr/packages/wallpapers.sh
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
sh ~/hyprtk/hypr/packages/fonts.sh
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
wal -i ~/hyprtk/Wallpapers/default.png
echo "pywal16 initiated."
echo ""
echo ""
echo "-> Copy default wallpaper to .cache"
cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png

if [ "$HAS_BOOT_GRUB_COPY" = true ]; then
    sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
fi

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
#                   Enabling Cockpit                    #
#                                                       #
#########################################################
"
sudo cp ~/hyprtk/distro/os-release/$DISTRO_ID $OS_RELEASE_PATH

if [ "$HAS_SPLASH" = true ]; then
    sudo cp ~/hyprtk/distro/splash/splash-arch.bmp /usr/share/systemd/bootctl/
    sudo mkinitcpio -P
fi

if [ "$HAS_CACHYOS_BRANDING" = true ]; then
    sudo cp ~/hyprtk/distro/os-release/$DISTRO_ID /run/systemd/propagate/.os-release-stage/
    sudo cp ~/hyprtk/distro/os-release/$DISTRO_ID /run/user/$UID/systemd/propagate/.os-release-stage/
    sudo cp ~/hyprtk/distro/os-release/cachyos-branding /usr/share/libalpm/scripts/
    sudo bash /usr/share/libalpm/scripts/cachyos-branding
fi

sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/
sudo systemctl enable --now cockpit.socket
sudo systemctl start cockpit.socket
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
sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
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
# name symlink source target
echo ""
echo ""
echo "-------------------------------------"
echo "-> Install general hyprtk"
echo "-------------------------------------"
echo ""
echo ""

if [ "$HYPR_BACKUP_POSITION" = "symlinks-before" ]; then
    mv ~/.config/hypr ~/.config/hypr-old
fi

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
echo "
#########################################################
#                                                       #
#                  Re-Initiating Pywal16                #
#                                                       #
#########################################################
"
echo ""
wal -i "$PYWAL_IMAGE"
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
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/hyprtk/gtk/gtk-3.0/ ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/hyprtk/gtk/gtk-4.0/ ~/.config/
_installSymLink themes ~/.local/share/themes ~/hyprtk/themes ~/.local/share/
_installSymLink icons ~/.local/share/icons ~/hyprtk/papirus-icons/icons ~/.local/share/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Xfce hyprtk"
echo "-------------------------------------"
echo ""
_installSymLink xfce4 ~/.config/xfce4 ~/hyprtk/xfce4 ~/.config/
_installSymLink Thunar ~/.config/Thunar ~/hyprtk/Thunar ~/.config/
_installSymLink Mousepad ~/.config/Mousepad ~/hyprtk/Mousepad ~/.config/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Hyprland hyprtk"
echo "-------------------------------------"
echo ""

if [ "$HYPR_BACKUP_POSITION" = "hypr-section" ]; then
    mv ~/.config/hypr ~/.config/hypr-old
fi

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
mkdir ~/.local/bin
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
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
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
_installSymLink .zshrc ~/.zshrc ~/hyprtk/.zshrc ~/.zshrc
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
_installSymLink standalone ~/.local/bin ~/hyprtk/standalone/ ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/hyprtk/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh
echo ""
rm -R $HOME/dotfiles
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Setup Root User Config"
echo "-------------------------------------"
echo ""
sudo cp -r ~/hyprtk/root /
echo " Copying Config and Themes to ROOT User "
echo ""
sleep 3

case "$SUDOERS_FORMAT" in
    reborn)
        echo -e '\n\tDefaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers
        ;;
    *)
        echo -e 'Defaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers
        ;;
esac

echo " Setup Password Feedback when entering SUDO password "
echo ""
sleep 3
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Congratulations Setup Complete"
echo "-------------------------------------"
echo ""
echo "DONE!"
echo ""
echo "NEXT: Update the keyboard layout and screen resolution in ~/hyprtk/hypr/hyprland.conf"
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""
