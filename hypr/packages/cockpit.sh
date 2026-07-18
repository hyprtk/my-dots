#!/bin/bash
figlet -f 3d "Cockpit"
echo " Cockpit "
sudo pacman -S cockpit cockpit-podman cockpit-machines --noconfirm
