#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Media"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg --noconfirm
yay -S hyprquickframe-git --noconfirm
echo ""
