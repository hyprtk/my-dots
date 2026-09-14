#!/bin/bash
# Non-interactive when -y/--yes is passed (used by the Theme Manager)
AUTO=""
case "$1" in
    -y|--yes) AUTO=1 ;;
esac
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "  HYPRTK · SDDM & GRUB Update"
echo "  Part of the Hyprtk desktop suite · github.com/hyprtk"
echo "─────────────────────────────────────────────────────────────────"
echo ""
if [ -z "$AUTO" ]; then
    while true; do
        read -p "Update the background wallpaper of GRUB & sddm to the current wallpaper NOW? (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                echo "Update started."
            break;;
            [Nn]* ) 
                echo "Update is Aborted"
                exit;
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
else
    echo "Update started."
fi
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
echo ""
# Resolve the desktop user's home (the script may run via pkexec/sudo where
# $HOME is /root). Used only to locate the user's dotfiles and wallpaper.
DESKTOP_HOME="$HOME"
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        DESKTOP_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    elif [ -n "${PKEXEC_UID:-}" ]; then
        DESKTOP_HOME="$(getent passwd "$PKEXEC_UID" | cut -d: -f6)"
    fi
fi
[ -n "$DESKTOP_HOME" ] || DESKTOP_HOME="$HOME"
WALLPAPER="$DESKTOP_HOME/.cache/current-wallpaper.png"

sudo cp "$DESKTOP_HOME/hyprtk/configs/sddm/sddm.conf" /etc/sddm.conf.d/
sudo cp "$DESKTOP_HOME/hyprtk/configs/sddm/sddm.conf" /etc/
echo "File /etc/sddm.conf updated."
echo ""
sudo cp "$WALLPAPER" /usr/share/sddm/themes/Sugar-Candy/Backgrounds/
echo "Current wallpaper copied into /usr/share/sddm/themes/Sugar-Candy/Backgrounds/"
echo ""
sudo cp "$DESKTOP_HOME/hyprtk/configs/sddm/theme.conf" /usr/share/sddm/themes/Sugar-Candy/
echo "File theme.conf updated in /usr/share/sddm/themes/Sugar-Candy/"
echo ""
sudo cp "$WALLPAPER" /root/.cache/current-wallpaper.png
echo ""

# ── GRUB ──────────────────────────────────────────────────────────────────
# Only touch GRUB when this machine actually boots GRUB. Never wipe
# /usr/share/grub/themes: dropping the GRUB_THEME assignment is enough for
# GRUB_BACKGROUND to be honoured.
if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
    echo " Enable OS-Prober"
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    sudo sed -i '/^GRUB_THEME=/d' /etc/default/grub
    echo ""
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | sudo tee -a /etc/default/grub
    echo ""
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo ""
    echo " Disable OS-Prober"
    sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    echo "GRUB updated with current wallpaper"
else
    echo "GRUB not detected (no grub-mkconfig / boot/grub/grub.cfg) - skipping GRUB steps"
fi
echo ""
echo "SDDM updated with current wallpaper"
echo ""
echo "Refreshing User Font Cache"
fc-cache -f
echo "User Font Cache updated "
echo "Refreshing System Font Cache"
sudo fc-cache -f
echo "System Font cache updated"
echo ""
echo "DONE! Please reboot to test GRUB & sddm update."
sleep 3
