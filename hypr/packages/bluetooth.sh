#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Bluetooth"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S bluez bluez-utils blueman --noconfirm
