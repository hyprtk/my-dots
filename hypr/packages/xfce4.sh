#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "XFCE4"
echo " XFCE4 "
_install_pacman xfce4 xfce4-goodies parole
_install_aur tumbler-extra-thumbnailers
