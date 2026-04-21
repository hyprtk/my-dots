#/bin/bash 
echo ""
echo " Welcome to the Hyprland & XFCE installer "
echo " I have chosen as my preference to install both, if you choose No on either Environments the installer will fail and close "
echo " I chose it this way so if 1 Enviroment has problems i still have the other to boot too, enjoy"
echo""
echo " You will now be asked to enter your Root password to proceed with the installation process"
echo""
sleep 2
sudo pacman -S figlet --noconfirm
sudo cp ~/my-dots/figlet/fonts/* /usr/share/figlet/fonts/
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
sudo pacman -Rns plasma kde-applications --noconfirm
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
sh ~/my-dots/scripts/set-timezone.sh
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
    cd ~/my-dots/
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
sh ~/my-dots/hypr/packages/graphics-card.sh
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
sh ~/my-dots/hypr/packages/hyprland.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/xfce4.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/filetools.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/webtools.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/printers.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/network.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/media.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/terminaltools.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/systemtools.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/system.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/hyprviz.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/sddm-check.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/sddmgrub.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/hypr/packages/matuwall.sh
echo ""
sleep 2
echo ""
sh ~/my-dots/scripts/awww-wrapper.sh
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
sh ~/my-dots/hypr/packages/wallpapers.sh
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
sh ~/my-dots/hypr/packages/fonts.sh
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
wal -i ~/my-dots/Wallpapers/default.png
echo "pywal16 initiated."
echo ""
echo ""
echo "-> Copy default wallpaper to .cache"
cp ~/my-dots/Wallpapers/default.png ~/.cache/current-wallpaper.png
sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
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
sudo cp ~/my-dots/User-Management/manage-users.desktop /usr/share/applications/
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
sudo cp ~/my-dots/smb/smb.conf /etc/samba/
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
echo "nvidia.conf file located ~/my-dots/hypr/conf/nvidia.conf"
echo ""
sleep 5
clear
figlet -f 3d "my-dots"
echo ""
echo " by hyprtk (Kori Tk) (2026) "
echo " ------------------------------------------------------------------- "
echo ""
echo "The script will ask for permission to remove existing directories and files from ~/.config/"
echo "Symbolic links will then be created from ~/my-dots into your ~/.config/ directory."
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
echo "-> Install general my-dots"
echo "-------------------------------------"
echo ""
echo ""
_installSymLink alacritty ~/.config/alacritty ~/my-dots/alacritty/ ~/.config
_installSymLink ranger ~/.config/ranger ~/my-dots/ranger/ ~/.config
_installSymLink vim ~/.config/vim ~/my-dots/vim/ ~/.config
_installSymLink nvim ~/.config/nvim ~/my-dots/nvim/ ~/.config
_installSymLink starship ~/.config/starship.toml ~/my-dots/starship/starship.toml ~/.config/starship.toml
_installSymLink rofi ~/.config/rofi ~/my-dots/rofi/ ~/.config
_installSymLink dunst ~/.config/dunst ~/my-dots/dunst/ ~/.config
_installSymLink wal ~/.config/wal ~/my-dots/wal/ ~/.config
_installSymLink btop ~/.config/btop ~/my-dots/btop/ ~/.config
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
wal -i ~/my-dots/Wallpapers/default.png
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
echo "-> Install GTK my-dots"
echo "-------------------------------------"
echo ""
_installSymLink gtk-3.0 ~/.config/gtk-3.0 ~/my-dots/gtk/gtk-3.0/ ~/.config/
_installSymLink gtk-4.0 ~/.config/gtk-4.0 ~/my-dots/gtk/gtk-4.0/ ~/.config/
_installSymLink themes ~/.local/share/themes ~/my-dots/themes ~/.local/share/
_installSymLink icons ~/.local/share/icons ~/my-dots/papirus-icons/icons ~/.local/share/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Xfce my-dots"
echo "-------------------------------------"
echo ""
_installSymLink xfce4 ~/.config/xfce4 ~/my-dots/xfce4 ~/.config/
_installSymLink Thunar ~/.config/Thunar ~/my-dots/Thunar ~/.config/
_installSymLink Mousepad ~/.config/Mousepad ~/my-dots/Mousepad ~/.config/
echo ""
clear
echo "-------------------------------------"
echo "-> Install Hyprland my-dots"
echo "-------------------------------------"
echo ""
_installSymLink hypr ~/.config/hypr ~/my-dots/hypr/ ~/.config
_installSymLink fastfetch ~/.config/fastfetch ~/my-dots/fastfetch/ ~/.config
_installSymLink waybar ~/.config/waybar ~/my-dots/waybar/ ~/.config
_installSymLink swaylock ~/.config/swaylock ~/my-dots/swaylock/ ~/.config
_installSymLink swappy ~/.config/swappy ~/my-dots/swappy/ ~/.config
_installSymLink hyprlogout ~/.config/hyprlogout ~/my-dots/hyprlogout/ ~/.config
_installSymLink waypaper ~/.config/waypaper ~/my-dots/waypaper/ ~/.config
_installSymLink zshrc ~/.config/zshrc ~/my-dots/zshrc/ ~/.config
_installSymLink ohmyposh ~/.config/ohmyposh ~/my-dots/ohmyposh/ ~/.config
_installSymLink matuwall ~/.config/matuwall ~/my-dots/matuwall/ ~/.config
_installSymLink wob ~/.config/wob ~/my-dots/wob/ ~/.config
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
_installSymLink .zshrc ~/.zshrc ~/my-dots/.zshrc ~/.zshrc
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
_installSymLink standalone ~/.local/bin ~/my-dots/standalone/ ~/.local/bin
_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh ~/my-dots/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh
echo ""
clear
echo ""
echo ""
echo "-------------------------------------"
echo "-> Setup Root User Config"
echo "-------------------------------------"
echo ""
sudo cp -r ~/my-dots/root /
echo " Copying Config and Themes to ROOT User "
echo ""
sleep 3
echo -e 'Defaults env_reset,pwfeedback'| sudo tee -a /etc/sudoers
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
echo "NEXT: Update the keyboard layout and screen resolution in ~/my-dots/hypr/hyprland.conf"
echo "Now proceed with rebooting your system and Enjoy!!!"
echo ""