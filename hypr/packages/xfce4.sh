#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "XFCE4"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S xfce4 xfce4-goodies parole --noconfirm
yay -S tumbler-extra-thumbnailers --noconfirm