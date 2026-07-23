#!/bin/bash

figlet -f 3d "Sys Tools"
echo " System Tools "
_install_pacman timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit
_install_aur gnome-disk-utility
echo ""
