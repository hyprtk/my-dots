#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Samba"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S samba smbclient cifs-utils --noconfirm
