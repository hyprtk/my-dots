#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "File Tools"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S thunar mousepad --noconfirm
echo ""
yay -S thunar-shares-plugin --noconfirm
echo ""