#!/bin/bash
figlet -f 3d "Samba"
echo " Samba "
sudo pacman -S samba smbclient cifs-utils --noconfirm
