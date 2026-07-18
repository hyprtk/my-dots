#!/bin/bash
figlet -f 3d "Bluetooth"
echo " Bluetooth "
sudo pacman -S bluez bluez-utils blueman --noconfirm
