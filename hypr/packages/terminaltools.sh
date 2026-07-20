#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Term Tools"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S eza micro xfce4-terminal btop alacritty kitty starship ranger nano figlet neovim --noconfirm
echo ""
yay -S fastfetch --noconfirm
echo ""
