#!/bin/bash
#
#
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "AppImage Launcher Setup"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S fuse
sudo modprobe fuse
echo ""
sudo pacman -S git base-devel
git clone https://aur.archlinux.org/trizen.git ~/.cache/yay
cd trizen/
makepkg -sri
trizen -S appimagelauncher
