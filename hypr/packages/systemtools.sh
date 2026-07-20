#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Sys Tools"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit --noconfirm
echo ""
yay -S gnome-disk-utility --noconfirm
echo ""