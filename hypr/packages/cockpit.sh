#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Cockpit"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S cockpit cockpit-podman cockpit-machines --noconfirm
