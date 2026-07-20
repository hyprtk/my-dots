#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "WebTools"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S chromium --noconfirm
echo ""
yay -S brave-bin github-desktop-bin --noconfirm
echo ""