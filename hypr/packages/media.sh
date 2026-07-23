#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "Media"
echo " Media Packages "
_install_pacman xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg
_install_aur hyprquickframe-git
echo ""
